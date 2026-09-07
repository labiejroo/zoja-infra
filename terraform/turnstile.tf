# ---------------------------------------------------------------------------
# WERYFIKACJA CAPTCHY — CLOUDFLARE TURNSTILE
#
# PROBLEM, KTÓRY TO ROZWIĄZUJE
# POST /api/reservations jest publiczny z natury: gość musi móc poprosić
# o termin bez logowania. Odkąd rezerwacja zapisuje prawdziwy adres e-mail
# i wywołuje wysyłkę poczty, każdy bot potrafi jednym skryptem zapchać
# kalendarz i wygenerować nam ruch w SES.
#
# DLACZEGO OSOBNA LAMBDA, A NIE WERYFIKACJA W API
# Siteverify to publiczny endpoint HTTPS, a API Lambda stoi w prywatnych
# podsieciach BEZ NAT Gateway — nie ma stamtąd żadnej trasy do internetu.
# Alternatywą byłby NAT (stała opłata godzinowa za jedno żądanie na rezerwację)
# albo proxy; wystawienie weryfikatora poza VPC nie kosztuje nic i korzysta
# z endpointu interfejsowego usługi Lambda, który już mamy dla poczty.
#
# ŻADNEGO NOWEGO ZASOBU SIECIOWEGO: bez NAT, bez drugiego VPC Endpointu,
# bez Function URL. Funkcję wywołuje wyłącznie API Lambda, przez IAM.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. SEKRET — SAM POJEMNIK, BEZ ZAWARTOŚCI
#
# ŚWIADOMIE BEZ aws_secretsmanager_secret_version, tak samo jak przy
# zoja/database i zoja/admin-auth. Klucz prywatny Turnstile wpisany do
# Terraforma wylądowałby jawnym tekstem w terraform.tfstate, czyli w pliku
# leżącym na dysku laptopa.
#
# Oczekiwany kształt wartości:
#
#   {"secretKey":"<klucz prywatny widgetu z panelu Cloudflare>"}
#
# Na tym etapie NIE MAMY jeszcze tego klucza — widget powstanie ręcznie
# w Cloudflare dopiero w etapie B. Sekret zostaje pusty i to jest w porządku:
# TURNSTILE_ENABLED jest false, więc nikt po niego nie sięga.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "turnstile" {
  name        = local.turnstile_secret_name
  description = "Klucz prywatny widgetu Cloudflare Turnstile. Wartosc ustawiana poza Terraformem."

  recovery_window_in_days = 7
}


# ---------------------------------------------------------------------------
# 2. ROLA — WŁASNA, NIE WSPÓŁDZIELONA
#
# Weryfikator nie potrzebuje ani bazy, ani poczty, ani prawa wywoływania czego-
# kolwiek. Za to jako jedyny czyta sekret Turnstile. Wspólna rola z API
# oznaczałaby, że publicznie wystawione API dostaje przy okazji dostęp do tego
# sekretu — bez żadnego powodu.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "turnstile_lambda" {
  name               = "${var.project}-turnstile-lambda-role"
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Logi zawężone do WŁASNEJ log groupy, nie do wszystkich Lambd w koncie.
data "aws_iam_policy_document" "turnstile_lambda_logs" {
  statement {
    effect  = "Allow"
    actions = ["logs:CreateLogGroup"]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.turnstile_log_group_name}:*"
    ]
  }
}

resource "aws_iam_policy" "turnstile_lambda_logs" {
  name        = "${local.name_prefix}-turnstile-lambda-logs"
  path        = "/service-role/"
  description = "CloudWatch Logs access for the Zoja Turnstile verifier"

  policy = data.aws_iam_policy_document.turnstile_lambda_logs.json
}

resource "aws_iam_role_policy_attachment" "turnstile_lambda_logs" {
  role       = aws_iam_role.turnstile_lambda.name
  policy_arn = aws_iam_policy.turnstile_lambda_logs.arn
}

# Odczyt JEDNEGO sekretu. Nie bazy, nie logowania gospodarzy, nie gwiazdki.
data "aws_iam_policy_document" "turnstile_lambda_secret" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.turnstile.arn]
  }
}

resource "aws_iam_policy" "turnstile_lambda_secret" {
  name        = "${local.name_prefix}-turnstile-lambda-secret-read"
  path        = "/service-role/"
  description = "Read-only access to the Zoja Turnstile secret"

  policy = data.aws_iam_policy_document.turnstile_lambda_secret.json
}

resource "aws_iam_role_policy_attachment" "turnstile_lambda_secret" {
  role       = aws_iam_role.turnstile_lambda.name
  policy_arn = aws_iam_policy.turnstile_lambda_secret.arn
}

# ŚWIADOMIE BRAK AWSLambdaVPCAccessExecutionRole — funkcja nie wchodzi do VPC,
# więc nie tworzy ENI i uprawnienia do zarządzania nimi byłyby nadmiarowe.
# Świadomie też: bez ses:SendEmail, bez dostępu do RDS i bez lambda:Invoke.


# ---------------------------------------------------------------------------
# 3. LOG GROUP
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "turnstile" {
  name = local.turnstile_log_group_name

  # Bez retention_in_days — tak samo jak pozostałe log groupy w projekcie.
  # Jedna konwencja, nie cztery.

  lifecycle {
    prevent_destroy = true
  }
}


# ---------------------------------------------------------------------------
# 4. SAMA FUNKCJA
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "turnstile" {
  function_name = local.turnstile_lambda_function_name
  role          = aws_iam_role.turnstile_lambda.arn

  runtime = var.lambda_runtime
  handler = "dist/turnstile-lambda.handler"

  # Ten sam wzorzec co przy pozostałych funkcjach: Terraform powołuje funkcję
  # do życia, prawdziwy artefakt wgrywa CI backendu przez
  # aws lambda update-function-code.
  filename = "${path.module}/placeholder/placeholder.zip"

  # Funkcja robi jedno wywołanie HTTPS i porównuje trzy pola. 128 MB wystarcza
  # z zapasem, a pamięć jest tu jednocześnie przydziałem CPU.
  memory_size = 128

  # 10 s przy timeoucie Siteverify 4 s i najwyżej jednym ponowieniu. Zapas jest
  # celowy: gdyby limity były równe, funkcja umierałaby zabita przez AWS zamiast
  # zwrócić czytelne „unavailable”.
  timeout = 10

  # ŻADNEGO vpc_config — TO JEST SEDNO TEJ FUNKCJI.
  # Poza VPC ma normalne wyjście do Cloudflare i do publicznego endpointu
  # Secrets Managera, bez NAT Gateway i bez dodatkowych endpointów.

  environment {
    variables = {
      NODE_ENV = "production"

      # Nazwa sekretu, nie jego wartość. Klucz prywatny widgetu nie ma prawa
      # znaleźć się w env: widzi ją każdy z lambda:GetFunctionConfiguration
      # i wsiąka do pliku stanu Terraforma.
      TURNSTILE_SECRET_ID = local.turnstile_secret_name

      # Po success=true weryfikator wymaga DOKŁADNEJ zgodności obu wartości.
      # Bez tego token zdobyty na innej stronie z tym samym kluczem publicznym
      # przechodziłby u nas, a token z innego formularza dałby się przenieść.
      TURNSTILE_EXPECTED_HOSTNAME = local.turnstile_expected_hostname
      TURNSTILE_EXPECTED_ACTION   = "reservation_create"
    }
  }

  # ŻADNEGO aws_lambda_permission i ŻADNEGO Function URL.
  # Funkcji nie wywołuje ani API Gateway, ani nic publicznego — wyłącznie
  # API Lambda, przez swoją rolę IAM. Publiczny wyzwalacz byłby darmowym
  # proxy do naszego limitu Siteverify.

  lifecycle {
    ignore_changes = [
      # Kodem zarządza CI backendu, nie Terraform.
      filename,
      source_code_hash,
      s3_bucket,
      s3_key,
      s3_object_version,
    ]
  }

  # Rola ma mieć podpięte polityki, ZANIM funkcja powstanie. Bez tego pierwsze
  # wywołanie mogłoby trafić na rolę bez dostępu do logów albo sekretu.
  depends_on = [
    aws_iam_role_policy_attachment.turnstile_lambda_logs,
    aws_iam_role_policy_attachment.turnstile_lambda_secret,
  ]
}


# ---------------------------------------------------------------------------
# 5. API LAMBDA → WERYFIKATOR
#
# Jedna akcja, jeden ARN. Nie lambda:*, nie Resource = "*".
#
# UWAGA NA SKUTEK UBOCZNY: tę rolę współdzieli Lambda migracyjna, więc
# formalnie ona także zyskuje prawo wywołania weryfikatora. To ten sam,
# zapisany już wcześniej dług co przy poczcie i sekrecie logowania —
# rozdzielenie ról zostaje na osobny, świadomy krok.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_invoke_turnstile" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.turnstile.arn]
  }
}

resource "aws_iam_policy" "lambda_invoke_turnstile" {
  name        = "${local.name_prefix}-lambda-invoke-turnstile"
  path        = "/service-role/"
  description = "Allow the Zoja API Lambda to invoke the Turnstile verifier only"

  policy = data.aws_iam_policy_document.lambda_invoke_turnstile.json
}

resource "aws_iam_role_policy_attachment" "lambda_invoke_turnstile" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_invoke_turnstile.arn
}


# ---------------------------------------------------------------------------
# CO TRZEBA ZROBIĆ RĘCZNIE W ETAPIE TURNSTILE B
#
# Świadomie NIE dodajemy providera Cloudflare do tego repozytorium. Projekt
# odwzorowuje AWS; drugi provider oznaczałby drugie poświadczenia i drugi
# obszar stanu — dla jednego widgetu to nieproporcjonalne.
#
#   1. Cloudflare Dashboard -> Turnstile -> Add widget
#        Name:     Zoja Reservations Production
#        Hostname: d3idn259a1zzt7.cloudfront.net   (domena CloudFrontu,
#                  NIE strona rodzinna na Netlify — dokument w iframe
#                  pochodzi z CloudFrontu i to jego widzi Cloudflare)
#        Mode:     Managed
#
#   2. SITE KEY (publiczny)  -> NEXT_PUBLIC_TURNSTILE_SITE_KEY przy budowaniu
#                               frontendu. Trafia do bundla, nie jest sekretem.
#
#   3. SECRET KEY (prywatny) -> aws secretsmanager put-secret-value
#                               --secret-id zoja/turnstile
#                               --secret-string '{"secretKey":"..."}'
#                               Nigdy do repo, nigdy do env Lambdy.
#
#   4. Deploy weryfikatora, deploy API, deploy frontendu, smoke.
#
#   5. Dopiero wtedy TURNSTILE_ENABLED = true i osobny apply.
#
# Kolejność ma znaczenie: włączenie wymuszania przed wdrożeniem frontendu
# z prawdziwym sitekey zablokowałoby formularz wszystkim gościom.
# ---------------------------------------------------------------------------
