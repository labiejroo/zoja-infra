# ---------------------------------------------------------------------------
# LAMBDA MIGRACYJNA
#
# ZASADA DZIAŁANIA
# Ten sam artefakt ZIP co Lambda API, inny handler, brak wyzwalacza. Funkcja
# stoi w tej samej VPC i tej samej grupie bezpieczeństwa, więc ma trasę do
# prywatnego RDS — trasę, której nie ma ani laptop, ani runner GitHuba.
#
# Uruchomienie migracji po wdrożeniu:
#
#   aws lambda invoke --function-name zoja-db-migrations-lambda response.json
#   cat response.json
#
# Dzięki temu nie musimy ani otwierać bazy na świat, ani wystawiać publicznego
# endpointu /api/migrate.
#
# NIC NOWEGO POZA SAMĄ FUNKCJĄ
# Rola IAM, grupa bezpieczeństwa, VPC Endpoint i sekret są współdzielone
# z Lambdą API. Uzasadnienie każdego z tych wyborów jest przy odpowiednich
# atrybutach niżej.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "migrations" {
  name = "/aws/lambda/zoja-db-migrations-lambda"

  # Bez retention_in_days — tak samo jak log group Lambdy API, która trzyma
  # logi bezterminowo. Jedna konwencja w projekcie, nie dwie.

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_lambda_function" "migrations" {
  function_name = "zoja-db-migrations-lambda"

  # TA SAMA ROLA CO LAMBDA API — świadomie.
  # Migracje potrzebują dokładnie tych samych uprawnień AWS: logów CloudWatch,
  # zarządzania ENI w VPC i GetSecretValue na jeden sekret. Uprawnienia do
  # CREATE TABLE czy ALTER TABLE nie należą do IAM — kontroluje je PostgreSQL.
  # Osobny użytkownik bazy dla migracji to temat na późniejszy hardening.
  role = aws_iam_role.lambda_exec.arn

  runtime = var.lambda_runtime
  handler = "dist/migration-lambda.handler"

  # Terraform tworzy funkcję, ale nie zarządza jej kodem. Prawdziwy artefakt
  # wgrywamy osobno przez aws lambda update-function-code, tak samo jak dla
  # Lambdy API. Ten plik służy wyłącznie do powołania funkcji do życia.
  filename = "${path.module}/placeholder/placeholder.zip"

  memory_size = 256
  timeout     = 60

  # BEZ reserved_concurrent_executions — nie z wyboru, tylko z ograniczenia.
  # Limit Concurrent Executions tego konta wynosi 10, a AWS wymaga, żeby po
  # rezerwacji zostało minimum 10 nieprzydzielonych. Rezerwacja JAKIEJKOLWIEK
  # wartości kończy się więc błędem 400 — to nie jest kwestia doboru liczby.
  # Przed równoległymi migracjami zabezpieczy nas concurrency group w GitHub
  # Actions, gdy dojdzie CI.

  # TE SAME SUBNETY I TA SAMA GRUPA CO LAMBDA API.
  # Dzięki temu funkcja dziedziczy gotowe ścieżki sieciowe bez jednej nowej
  # reguły: RDS SG wpuszcza 5432 z tej grupy, a SG endpointu Secrets Managera
  # wpuszcza z niej 443.
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

      # ŻADNEGO DB_PASSWORD — ta funkcja rodzi się już po cutoverze.
      # Hasło pobiera ensureDatabasePassword() z Secrets Managera i trzyma je
      # wyłącznie w pamięci procesu, zanim dynamicznie zaimportuje data-source.
      DB_SECRET_ID = local.database_secret_name
    }
  }

  # ŻADNEGO aws_lambda_permission dla tej funkcji.
  # Nie ma być wywoływalna przez API Gateway ani cokolwiek publicznego.

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

  # Uprawnienia i sekret muszą istnieć, ZANIM funkcja powstanie. Bez tego
  # pierwsze wywołanie mogłoby trafić na rolę bez podpiętych polityk.
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy_attachment.lambda_secrets,
    aws_secretsmanager_secret.database,
  ]
}
