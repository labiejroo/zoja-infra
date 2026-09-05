# ---------------------------------------------------------------------------
# LAMBDA MAILOWA — ZASÓB NOWY, NIE IMPORTOWANY
#
# DLACZEGO OSOBNA FUNKCJA, A NIE WYSYŁKA Z LAMBDY API
#
# Powód pierwszy, sieciowy: Lambda API stoi w prywatnych podsieciach bez NAT
# Gateway, więc nie ma trasy do publicznego endpointu SES. Wystawienie tej
# funkcji POZA VPC daje jej normalne wyjście do internetu bez ani jednego
# nowego zasobu sieciowego i bez opłaty godzinowej za NAT.
#
# Powód drugi, ważniejszy: uprawnienia. To TA funkcja dostaje ses:SendEmail,
# a publicznie wystawiona Lambda API nie dostaje go nigdy. Gdyby ktoś znalazł
# dziurę w publicznym API, nie zyskuje tym samym możliwości wysyłania poczty
# z naszego adresu. Rozdzielenie jest tu warte osobnej funkcji.
#
# CO TA FUNKCJA WIE, A CZEGO NIE
# Nie zna bazy: bez TypeORM, bez RDS, bez sekretu, bez DB_SECRET_ID. Dostaje
# gotowe zdarzenie z payloadem i buduje z niego wiadomość. Dlatego nie
# potrzebuje ani podsieci, ani zoja-lambda-sg, ani endpointu Secrets Managera.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "mail" {
  name = local.mail_log_group_name

  # Bez retention_in_days — tak samo jak log groupy Lambdy API i migracyjnej.
  # Jedna konwencja w projekcie, nie trzy.

  lifecycle {
    prevent_destroy = true
  }
}


# ---------------------------------------------------------------------------
# ROLA — WŁASNA, NIE WSPÓŁDZIELONA
#
# Lambda migracyjna dzieli rolę z API, bo potrzebuje DOKŁADNIE tych samych
# uprawnień: logów, ENI w VPC i jednego sekretu. Tutaj jest odwrotnie — ta
# funkcja nie potrzebuje ani ENI, ani sekretu, ani RDS, za to jako jedyna ma
# dostać ses:SendEmail. Wspólna rola oznaczałaby, że publiczne API również
# może wysyłać maile, czyli przekreślałaby cały powód istnienia tej funkcji.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "mail_lambda" {
  name               = "${var.project}-mail-lambda-role"
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Logi zawężone do WŁASNEJ log groupy tej funkcji, nie do wszystkich Lambd
# w koncie. Ten sam kształt polityki co lambda_logs w iam.tf.
data "aws_iam_policy_document" "mail_lambda_logs" {
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
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.mail_log_group_name}:*"
    ]
  }
}

resource "aws_iam_policy" "mail_lambda_logs" {
  name        = "${local.name_prefix}-mail-lambda-logs"
  path        = "/service-role/"
  description = "CloudWatch Logs access for the Zoja mail Lambda"

  policy = data.aws_iam_policy_document.mail_lambda_logs.json
}

resource "aws_iam_role_policy_attachment" "mail_lambda_logs" {
  role       = aws_iam_role.mail_lambda.name
  policy_arn = aws_iam_policy.mail_lambda_logs.arn
}

# ŚWIADOMIE BRAK AWSLambdaVPCAccessExecutionRole.
# Ta funkcja nie wchodzi do VPC, więc nie tworzy ENI i uprawnienia do
# zarządzania nimi byłyby nadmiarowe.


# ---------------------------------------------------------------------------
# UPRAWNIENIE DO WYSYŁKI — POWSTAJE DOPIERO Z ADRESEM NADAWCY
#
# Dopóki var.ses_from_email jest puste, tej polityki NIE MA. Nie ma po co:
# nie wiadomo jeszcze, z jakiego adresu wysyłamy, a polityka z Resource = "*"
# wpisana "na teraz, doprecyzujemy później" zwykle zostaje na zawsze.
#
# GDY ADRES JEST ZNANY, OGRANICZAMY DWUKROTNIE:
#
#   1. Resource — do ARN konkretnej tożsamości SES. ses:SendEmail wspiera
#      uprawnienia na poziomie zasobu, więc to jest właściwe narzędzie
#      i nie musimy sięgać po Resource = "*".
#
#   2. Warunek ses:FromAddress — bo ARN tożsamości domenowej obejmuje KAŻDY
#      adres w tej domenie. Przy tożsamości adresowej warunek jest
#      redundantny, ale po przejściu na domenę stanie się jedyną rzeczą
#      trzymającą nas przy jednym nadawcy. Taniej dodać go teraz.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mail_lambda_ses" {
  count = local.ses_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["ses:SendEmail"]

    resources = [local.ses_identity_arn]

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [trimspace(var.ses_from_email)]
    }
  }
}

resource "aws_iam_policy" "mail_lambda_ses" {
  count = local.ses_enabled ? 1 : 0

  name        = "${local.name_prefix}-mail-lambda-ses-send"
  path        = "/service-role/"
  description = "Send email through one specific SES identity"

  policy = data.aws_iam_policy_document.mail_lambda_ses[0].json
}

resource "aws_iam_role_policy_attachment" "mail_lambda_ses" {
  count = local.ses_enabled ? 1 : 0

  role       = aws_iam_role.mail_lambda.name
  policy_arn = aws_iam_policy.mail_lambda_ses[0].arn
}


# ---------------------------------------------------------------------------
# SAMA FUNKCJA
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "mail" {
  function_name = local.mail_lambda_function_name
  role          = aws_iam_role.mail_lambda.arn

  runtime = var.lambda_runtime
  handler = "dist/mail-lambda.handler"

  # Ten sam wzorzec co przy pozostałych funkcjach: Terraform powołuje funkcję
  # do życia, prawdziwy artefakt wgrywa CI backendu przez
  # aws lambda update-function-code. Ten plik nie jest kodem aplikacji.
  filename = "${path.module}/placeholder/placeholder.zip"

  # Funkcja składa string i robi jedno wywołanie HTTPS. 128 MB wystarcza
  # z zapasem, a pamięć jest tu jednocześnie przydziałem CPU — dokładanie jej
  # przy takim obciążeniu podnosi tylko rachunek.
  memory_size = 128

  # 15 s to zapas na zimny start plus jedno wywołanie SES. Lambda API czeka na
  # odpowiedź synchronicznie (InvocationType = RequestResponse), więc ten
  # timeout jest jednocześnie górnym opóźnieniem, jakie może zobaczyć gość
  # wysyłający prośbę o wizytę.
  timeout = 15

  # ŻADNEGO vpc_config — TO JEST SEDNO TEJ FUNKCJI.
  # Poza VPC ma normalne wyjście do SES bez NAT Gateway. Wpisanie tu podsieci
  # odcięłoby ją od internetu i wymagałoby albo NAT-a, albo endpointu SES.

  environment {
    variables = {
      NODE_ENV = "production"

      # Wartości mogą być na tym etapie puste. Funkcja sprawdza je dopiero przy
      # wywołaniu (requireEnv) i odmawia wysyłki, gdy ich brakuje — a wywołana
      # i tak nie zostanie, dopóki EMAIL_ENABLED w Lambdzie API jest "false".
      SES_FROM_EMAIL = trimspace(var.ses_from_email)

      # Lista rozdzielona przecinkami: zmienne środowiskowe Lambdy są płaskimi
      # stringami, a JSON w env dawałby drugi format do pilnowania.
      PARENT_NOTIFICATION_EMAILS = join(",", var.parent_notification_emails)

      # BEZ FRAGMENTU. Część po # dokleja szablon maila razem z tokenem decyzji.
      ACTION_PAGE_URL = local.action_page_url
    }
  }

  # ŻADNEGO aws_lambda_permission.
  # Tej funkcji nie wywołuje API Gateway ani nic publicznego — wyłącznie Lambda
  # API, przez swoją rolę IAM. Uprawnienie po stronie wywołującego wystarcza,
  # bo obie funkcje należą do tego samego konta.

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

  # Rola ma mieć podpiętą politykę logów, ZANIM funkcja powstanie. Bez tego
  # pierwsze wywołanie mogłoby trafić na rolę bez uprawnień do CloudWatch.
  depends_on = [aws_iam_role_policy_attachment.mail_lambda_logs]
}


# ---------------------------------------------------------------------------
# LAMBDA API → LAMBDA MAILOWA
#
# Jedna akcja, jeden ARN. Nie lambda:*, nie Resource = "*".
#
# UWAGA NA SKUTEK UBOCZNY: tę rolę współdzieli Lambda migracyjna
# (lambda-migrations.tf), więc formalnie ona także zyskuje prawo wywołania
# funkcji mailowej. Nie rozdzielamy tego dziś, bo osobna rola dla migracji
# oznaczałaby zmianę działającej funkcji produkcyjnej przy okazji etapu
# o mailach. Kod migracji nie zawiera wywołania Mail Lambdy, a rozdzielenie
# ról zostaje na osobny, świadomy krok.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_invoke_mail" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.mail.arn]
  }
}

resource "aws_iam_policy" "lambda_invoke_mail" {
  name        = "${local.name_prefix}-lambda-invoke-mail"
  path        = "/service-role/"
  description = "Allow the Zoja API Lambda to invoke the mail Lambda only"

  policy = data.aws_iam_policy_document.lambda_invoke_mail.json
}

resource "aws_iam_role_policy_attachment" "lambda_invoke_mail" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_invoke_mail.arn
}
