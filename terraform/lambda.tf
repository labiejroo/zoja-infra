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
      # DB_PASSWORD CELOWO NIE JEST TUTAJ.
      # Ustawiane ręcznie w konsoli Lambdy jako świadome uproszczenie na czas
      # laba. Wpisanie go tutaj umieściłoby hasło w pliku stanu Terraforma.
      # Patrz README, sekcja o sekretach.
    }
  }

  # OCHRONA RDS PRZED LAWINĄ POŁĄCZEŃ
  # Górny limit połączeń do bazy to w przybliżeniu:
  #     liczba równoległych środowisk wykonawczych x DB_POOL_MAX
  # Backend trzyma małą pulę (DB_POOL_MAX=2), a tutaj ograniczamy drugi czynnik.
  # Oba mają znaczenie — jedno bez drugiego nie wystarcza.
  # TODO: ustal wartość i odkomentuj. Wymaga apply, więc świadoma decyzja.
  # reserved_concurrent_executions = 10

  lifecycle {
    ignore_changes = [
      # Kodem zarządza CI backendu, nie Terraform.
      filename,
      source_code_hash,
      s3_bucket,
      s3_key,
      s3_object_version,
      # DB_PASSWORD ustawiane ręcznie poza Terraformem. Bez tego każdy plan
      # chciałby usunąć je ze zmiennych środowiskowych funkcji.
      environment,
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
