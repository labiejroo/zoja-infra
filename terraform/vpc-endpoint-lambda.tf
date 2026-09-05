# ---------------------------------------------------------------------------
# INTERFACE VPC ENDPOINT DLA USŁUGI LAMBDA
#
# PO CO
# Lambda API stoi w prywatnych podsieciach bez NAT Gateway, więc nie ma trasy
# do publicznego lambda.eu-central-1.amazonaws.com. Sama polityka IAM tego nie
# naprawia — pakiet z InvokeCommand po prostu nie ma dokąd wyjść i wywołanie
# kończy się timeoutem, a nie odmową.
#
# Endpoint wstawia do podsieci ENI z adresem prywatnym, a private_dns_enabled
# sprawia, że publiczna nazwa usługi rozwiązuje się WEWNĄTRZ VPC na ten adres.
# Dzięki temu MailDispatcherService używa zwykłego LambdaClient z AWS SDK,
# bez żadnego custom endpoint URL w kodzie.
#
# KOSZT
# Ok. 0,011 USD/h za ENI w każdej strefie, czyli przy jednej strefie ok. 8 USD
# miesięcznie niezależnie od liczby wywołań. To druga taka pozycja w projekcie
# — pierwsza jest przy Secrets Managerze.
# ---------------------------------------------------------------------------

resource "aws_security_group" "lambda_endpoint" {
  name        = "${var.project}-lambda-endpoint-sg"
  description = "Ingress HTTPS to Lambda interface endpoint from Zoja Lambda only"
  vpc_id      = data.aws_vpc.default.id
}

# Jedyne dozwolone wejście: 443 z grupy Lambdy. Ani 0.0.0.0/0, ani CIDR całej
# VPC — endpoint nie ma powodu przyjmować ruchu od czegokolwiek innego, a
# źródło w postaci grupy jest węższe i nie wymaga pilnowania adresacji.
resource "aws_vpc_security_group_ingress_rule" "lambda_endpoint_from_lambda" {
  security_group_id = aws_security_group.lambda_endpoint.id

  description = "HTTPS from Zoja API Lambda"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

# CELOWY BRAK REGUŁY WYJŚCIOWEJ — dokładnie jak przy endpoincie Secrets
# Managera. Grupy bezpieczeństwa są stanowe, więc odpowiedź na dozwolone
# połączenie przychodzące wraca niezależnie od reguł egress, a endpoint sam
# z siebie nigdzie nie inicjuje połączeń.

resource "aws_vpc_endpoint" "lambda" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.lambda"
  vpc_endpoint_type = "Interface"

  # JEDNA strefa — ten sam świadomy kompromis kosztowy co przy Secrets
  # Managerze. Cena: Lambda z drugiej podsieci sięga tu przez granicę stref,
  # a awaria tej jednej strefy odcina wysyłkę maili. Rezerwacja jest po
  # stronie produktu akceptowalna: nieudany mail nie cofa rezerwacji.
  subnet_ids = [
    "subnet-073cce418a6ab9fe4",
  ]

  security_group_ids  = [aws_security_group.lambda_endpoint.id]
  private_dns_enabled = true

  # ŚWIADOMIE BEZ WŁASNEJ POLITYKI ENDPOINTU.
  #
  # Domyślna polityka jest szeroka, ale nie jest tu jedyną kontrolą. Dostęp do
  # funkcji mailowej ograniczają już dwie niezależne rzeczy:
  #
  #   1. grupa bezpieczeństwa wyżej — do endpointu dosięgają wyłącznie zasoby
  #      w zoja-lambda-sg, czyli nasze dwie Lambdy;
  #   2. polityka roli wywołującej — lambda:InvokeFunction na JEDEN ARN
  #      (patrz aws_iam_policy.lambda_invoke_mail).
  #
  # Trzecia kopia tej samej reguły musiałaby być utrzymywana równolegle
  # z dwiema poprzednimi, a jej rozjechanie objawia się timeoutem zamiast
  # czytelnego AccessDenied — czyli najgorszym możliwym trybem awarii.
  # Dokładamy ją dopiero, gdy przez ten endpoint zacznie chodzić coś więcej
  # niż jedno wywołanie jednej funkcji.

  tags = {
    Name = "${local.name_prefix}-lambda-endpoint"
  }
}
