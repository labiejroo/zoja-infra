# ---------------------------------------------------------------------------
# LAMBDA API — ISTNIEJE, DO IMPORTU
#
# PODZIAŁ ODPOWIEDZIALNOŚCI
# Terraform opisuje KONFIGURACJĘ funkcji: rolę, sieć, pamięć, timeout, zmienne
# środowiskowe. KODU nie dotyka — wgrywa go CI backendu przez
# aws lambda update-function-code. Dzięki temu zwykła zmiana w backendzie nigdy
# nie wymaga terraform apply, a Terraform nie widzi dryfu po każdym deployu.
# Realizuje to blok lifecycle na końcu zasobu.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api" {
  name = local.api_log_group_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_function" "api" {
  function_name = var.api_lambda_function_name
  role          = aws_iam_role.lambda_exec.arn

  runtime = var.lambda_runtime
  handler = "dist/lambda.handler"

  # Terraform wymaga wskazania źródła kodu, nawet gdy go nie zarządza.
  # Ten plik jest używany WYŁĄCZNIE gdyby funkcja powstawała od zera.
  # Przy imporcie istniejącej funkcji nie zostanie użyty ani razu.
  filename = "${path.module}/placeholder/placeholder.zip"

  memory_size = 256
  timeout     = 10

  vpc_config {
    subnet_ids = [
      "subnet-073cce418a6ab9fe4",
      "subnet-04099219aa563a772",
    ]

    security_group_ids = [
      aws_security_group.lambda.id
    ]
  }

  environment {
    variables = {
      NODE_ENV = "production"
      DB_HOST  = aws_db_instance.postgres.address
      DB_PORT  = tostring(aws_db_instance.postgres.port)
      DB_NAME  = var.rds_database_name
      DB_USER  = var.rds_username
      DB_SSL   = "true"

      # Wskazuje, SKĄD wziąć hasło. Nazwa sekretu sekretem nie jest, więc
      # Terraform może nią spokojnie zarządzać. Backend sięga po tę zmienną
      # DOPIERO gdy DB_PASSWORD nie istnieje — patrz ensureDatabasePassword()
      # — więc dopóki hasło zostaje w env, produkcja działa jak dotąd.
      #
      # CELOWO nazwa, a NIE aws_secretsmanager_secret.database.arn.
      # ARN ma losowy sufiks, więc jest nieznany przed utworzeniem sekretu.
      # Jedna nieznana wartość sprawia, że provider oznacza CAŁĄ mapę jako
      # (known after apply), a wtedy plan przestaje dowodzić, że DB_PASSWORD
      # przetrwa. Znany literał utrzymuje mapę policzalną na etapie planu.
      DB_SECRET_ID = local.database_secret_name

      # DB_PASSWORD CELOWO NIE JEST TUTAJ — i nie ma go już także w samej
      # Lambdzie. Hasło pobiera backend przy starcie z Secrets Managera,
      # wskazanego przez DB_SECRET_ID, i trzyma je wyłącznie w pamięci
      # procesu. Wpisanie go tutaj umieściłoby je w pliku stanu Terraforma,
      # czyli dokładnie tam, skąd je wyprowadziliśmy.

      # --- WYSYŁKA MAILI ---
      #
      # WYŁĄCZNIK ZOSTAJE NA "false" PO APPLY.
      #
      # Cały tor mailowy wdrażamy martwy: kod jest na miejscu, funkcja istnieje,
      # uprawnienia są nadane, a mimo to MailDispatcherService przy każdym
      # zdarzeniu wychodzi wcześniej i nie dotyka SDK. Włączenie wysyłki to
      # osobna, świadoma zmiana tej jednej wartości — nie skutek uboczny
      # wdrożenia infrastruktury.
      #
      # Wartość bierze się ze zmiennej, której default to false — włączenie
      # wysyłki jest wtedy zmianą w repozytorium, a nie kliknięciem w konsoli.
      # Do włączenia potrzebne są wcześniej trzy rzeczy: zweryfikowany nadawca,
      # Production Access w SES i decyzja o autoryzacji /api/admin/*.
      EMAIL_ENABLED = tostring(var.email_enabled)

      # Nazwa funkcji, a nie ARN — SDK przyjmuje jedną i drugą, a nazwa jest
      # literałem znanym na etapie planu. Przy ARN-ie (nieznanym przed
      # utworzeniem funkcji) provider oznaczyłby CAŁĄ mapę environment jako
      # (known after apply) i plan przestałby dowodzić, co dzieje się
      # z pozostałymi zmiennymi. Ta sama pułapka co przy DB_SECRET_ID.
      MAIL_LAMBDA_FUNCTION_NAME = aws_lambda_function.mail.function_name
    }
  }

  # OCHRONA RDS PRZED LAWINĄ POŁĄCZEŃ
  # Górny limit połączeń do bazy to w przybliżeniu:
  #     liczba równoległych środowisk wykonawczych x DB_POOL_MAX
  # Backend trzyma małą pulę (DB_POOL_MAX=2), a tutaj ograniczamy drugi czynnik.
  # Oba mają znaczenie — jedno bez drugiego nie wystarcza.
  # TODO: ustal wartość i odkomentuj. Wymaga apply, więc świadoma decyzja.
  # reserved_concurrent_executions = 10

  # Nazwa sekretu jest literałem, więc Terraform nie wywnioskuje tej
  # zależności sam. Deklarujemy ją jawnie: sekret ma istnieć, zanim Lambda
  # zacznie na niego wskazywać.
  depends_on = [aws_secretsmanager_secret.database]

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
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGatewayApiProxy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http.execution_arn}/*/*/api/*"

  lifecycle {
    create_before_destroy = true
  }
}
