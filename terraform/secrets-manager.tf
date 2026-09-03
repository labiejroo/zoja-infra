# ---------------------------------------------------------------------------
# SECRETS MANAGER — ZASOBY NOWE, NIE IMPORTOWANE
#
# PO CO TO ROBIMY
# Hasło do bazy leży dziś w zmiennej środowiskowej Lambdy. Zmienna środowiskowa
# jest jawna dla każdego, kto ma lambda:GetFunctionConfiguration, widać ją w
# konsoli i wsiąka do pliku stanu Terraforma. Secrets Manager daje zamiast tego
# kontrolę dostępu per-IAM, ślad w CloudTrailu przy każdym odczycie i miejsce,
# w którym da się później włączyć rotację.
#
# TO JEST ETAP B, NIE CUTOVER
# Ten plik dokłada wyłącznie infrastrukturę. Nie ustawia wartości sekretu i nie
# usuwa DB_PASSWORD z Lambdy. Dopóki DB_PASSWORD istnieje, funkcja
# ensureDatabasePassword() w backendzie kończy się na pierwszym ifie i w ogóle
# nie dotyka Secrets Managera. Ścieżka produkcyjna zostaje nietknięta.
#
# KOSZT
# Interface VPC Endpoint to jedyna pozycja w tej zmianie, która realnie kosztuje:
# ok. 0,011 USD/h za ENI w każdej strefie dostępności, czyli przy dwóch strefach
# ok. 16 USD miesięcznie, niezależnie od tego, ile razy sekret zostanie odczytany.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# 1. SEKRET — SAM POJEMNIK, BEZ ZAWARTOŚCI
#
# Rozróżnienie, które przesądza o bezpieczeństwie tej zmiany:
#
#   aws_secretsmanager_secret         = metadane: nazwa, ARN, polityka, tagi
#   aws_secretsmanager_secret_version = TREŚĆ sekretu
#
# Tworzymy świadomie tylko pierwsze. Gdyby hasło trafiło do
# aws_secretsmanager_secret_version.secret_string, Terraform zapisałby je jawnym
# tekstem w terraform.tfstate — czyli odtworzyłby dokładnie ten problem, przed
# którym uciekamy. Wartość wgramy osobno, przez AWS CLI, w ETAPIE C.
#
# Format wartości, którego oczekuje backend (ensureDatabasePassword):
#
#   {"password":"..."}
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "database" {
  name        = local.database_secret_name
  description = "Haslo uzytkownika RDS dla backendu Zoja. Wartosc ustawiana poza Terraformem."

  # Po usunięciu sekret czeka w koszu i da się go przywrócić. Wartość 0 oznacza
  # kasowanie natychmiastowe i nieodwracalne — tego nie chcemy nawet w labie.
  recovery_window_in_days = 7
}


# ---------------------------------------------------------------------------
# 2. DROGA SIECIOWA — INTERFACE VPC ENDPOINT
#
# Lambda pracuje w podsieciach bez NAT Gateway, więc nie ma żadnej trasy do
# publicznego adresu secretsmanager.eu-central-1.amazonaws.com. Sama polityka
# IAM tego nie naprawia — pakiet po prostu nie ma dokąd wyjść.
#
# Interface Endpoint wstawia do naszych podsieci ENI z adresem prywatnym, a
# private_dns_enabled sprawia, że publiczna nazwa DNS usługi rozwiązuje się
# WEWNĄTRZ VPC właśnie na ten adres. Dlatego kod backendu nie potrzebuje żadnego
# custom endpoint URL — zwykły SecretsManagerClient z AWS SDK trafia gdzie trzeba.
# ---------------------------------------------------------------------------

resource "aws_security_group" "secretsmanager_endpoint" {
  name        = "${var.project}-secrets-manager-endpoint-sg"
  description = "Ingress HTTPS to Secrets Manager interface endpoint from Zoja Lambda only"
  vpc_id      = data.aws_vpc.default.id
}

# Jedyne dozwolone wejście: 443 z grupy Lambdy. Nie 0.0.0.0/0 — endpoint nie ma
# powodu przyjmować ruchu od czegokolwiek innego w tej VPC.
resource "aws_vpc_security_group_ingress_rule" "secretsmanager_endpoint_from_lambda" {
  security_group_id = aws_security_group.secretsmanager_endpoint.id

  description = "HTTPS from Zoja API Lambda"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

# CELOWY BRAK REGUŁY WYJŚCIOWEJ
# Grupy bezpieczeństwa są stanowe: odpowiedź na dozwolone połączenie przychodzące
# wraca zawsze, niezależnie od reguł egress. Endpoint sam z siebie nigdzie nie
# inicjuje połączeń, więc pusty egress jest tu poprawny, a nie przeoczony.
# Terraform przy zakładaniu nowej grupy usuwa domyślne "wypuszczaj wszystko",
# które AWS dodaje automatycznie — i dobrze.

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"

  # JEDNA strefa — świadoma decyzja kosztowa na czas laba. Interface Endpoint
  # płaci się od ENI w każdej strefie, więc druga podsieć podwaja stałą opłatę.
  # Cena tej oszczędności: Lambda z drugiej podsieci sięga tu przez granicę
  # stref (drobny płatny transfer), a awaria tej jednej strefy odcina dostęp
  # do sekretu. Przed produkcją dołóż drugą podsieć z vpc_config w lambda.tf.
  subnet_ids = [
    "subnet-073cce418a6ab9fe4",
  ]

  security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-secretsmanager-endpoint"
  }
}


# ---------------------------------------------------------------------------
# 3. UPRAWNIENIE — ODCZYT JEDNEGO KONKRETNEGO SEKRETU
#
# Aplikacja ma sekret czytać i nic ponad to. Żadnego PutSecretValue, żadnego
# CreateSecret, żadnego ListSecrets, żadnego Resource = "*". Gdyby kod Lambdy
# został kiedyś przejęty, napastnik dostaje dokładnie tyle, ile ta funkcja i tak
# już trzyma w pamięci — i ani grama więcej.
#
# kms:Decrypt nie jest potrzebne, bo sekret szyfruje domyślny klucz zarządzany
# przez AWS (aws/secretsmanager), którego polityka sama dopuszcza odszyfrowanie
# przez Secrets Managera na rzecz principali z naszego konta. Gdybyśmy kiedyś
# podłożyli własny klucz CMK, trzeba by tu dopisać kms:Decrypt na jego ARN.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.database.arn]
  }
}

resource "aws_iam_policy" "lambda_secrets" {
  name        = "${local.name_prefix}-lambda-secrets-read"
  path        = "/service-role/"
  description = "Read-only access to the Zoja database secret"

  policy = data.aws_iam_policy_document.lambda_secrets.json
}

resource "aws_iam_role_policy_attachment" "lambda_secrets" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_secrets.arn
}
