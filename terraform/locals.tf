locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Log group Lambdy nazywa się zawsze według tego wzorca.
  api_log_group_name = "/aws/lambda/${var.api_lambda_function_name}"

  # Nazwa sekretu z hasłem do bazy. Trzymana tutaj, bo używają jej DWA miejsca:
  # zasób aws_secretsmanager_secret oraz zmienna DB_SECRET_ID w Lambdzie.
  #
  # DB_SECRET_ID musi dostać wartość ZNANĄ NA ETAPIE PLANU. Gdyby wskazywała
  # na ARN sekretu, ten byłby nieznany przed utworzeniem (losowy sufiks), a
  # jedna nieznana wartość degraduje u providera całą mapę environment do
  # (known after apply) — i plan przestaje pokazywać, co dzieje się z
  # DB_PASSWORD. GetSecretValue przyjmuje nazwę równie dobrze jak ARN.
  database_secret_name = "${var.project}/database"

  # --- WYSYŁKA MAILI ---

  mail_lambda_function_name = "${var.project}-mail-lambda"
  mail_log_group_name       = "/aws/lambda/${var.project}-mail-lambda"

  # Pusty adres nadawcy = cała gałąź SES wyłączona. Jedna flaga zamiast
  # powtarzanego warunku przy każdym zasobie.
  ses_enabled = trimspace(var.ses_from_email) != ""

  # ARN tożsamości SES składamy sami, bo przy pustym adresie nie ma zasobu,
  # z którego dałoby się go odczytać. Kształt jest ten sam dla tożsamości
  # domenowej i adresowej: identity/<nazwa>.
  ses_identity_arn = local.ses_enabled ? format(
    "arn:aws:ses:%s:%s:identity/%s",
    var.aws_region,
    data.aws_caller_identity.current.account_id,
    trimspace(var.ses_from_email),
  ) : ""

  # Nadawca i odbiorcy testowi w jednym zbiorze. toset() usuwa duplikat, gdyby
  # ten sam adres wystąpił w obu miejscach — inaczej dwa zasoby walczyłyby
  # o tę samą tożsamość.
  ses_identities = toset(concat(
    local.ses_enabled ? [trimspace(var.ses_from_email)] : [],
    var.ses_test_recipient_emails,
  ))

  # Domyślnie bierzemy domenę CloudFrontu, zamiast zapisywać ją na sztywno.
  # Po dołożeniu własnej domeny wystarczy ustawić zmienną — linki w mailach
  # przestawią się bez zmiany kodu.
  action_page_url = var.action_page_url != "" ? var.action_page_url : "https://${aws_cloudfront_distribution.main.domain_name}/decision"

  # --- LOGOWANIE GOSPODARZY ---
  #
  # Nazwa sekretu, tak samo jak przy bazie, jest LITERAŁEM znanym na etapie
  # planu. Trafia do zmiennej środowiskowej Lambdy, a ARN (z losowym sufiksem)
  # degradowałby całą mapę environment do (known after apply).
  admin_auth_secret_name = "${var.project}/admin-auth"

  # --- WERYFIKACJA TURNSTILE ---

  turnstile_lambda_function_name = "${var.project}-turnstile-lambda"
  turnstile_log_group_name       = "/aws/lambda/${var.project}-turnstile-lambda"

  # Nazwa sekretu, nie ARN — ta sama zasada co przy bazie i logowaniu:
  # ARN ma losowy sufiks, więc jest nieznany przed utworzeniem, a jedna
  # nieznana wartość degraduje całą mapę environment do (known after apply).
  turnstile_secret_name = "${var.project}/turnstile"

  # Host, który Cloudflare zobaczy przy rozwiązywaniu wyzwania.
  #
  # To domena CLOUDFRONTU, nie strony rodzinnej na Netlify. Formularz bywa
  # osadzony w iframe, ale dokument z widgetem pochodzi stąd — i to ten adres
  # Cloudflare wpisuje w pole hostname odpowiedzi Siteverify.
  turnstile_expected_hostname = aws_cloudfront_distribution.main.domain_name
}
