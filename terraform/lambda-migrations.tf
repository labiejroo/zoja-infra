# ---------------------------------------------------------------------------
# LAMBDA MIGRACYJNA — JESZCZE NIE ISTNIEJE W AWS
#
# Ten plik jest CELOWO w całości zakomentowany. Zasoby poniżej nie mają
# odpowiednika w AWS, więc nie podlegają importowi — powstaną dopiero
# świadomym terraform apply, po Twojej decyzji.
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
# ---------------------------------------------------------------------------

# resource "aws_cloudwatch_log_group" "migrations" {
#   name              = "/aws/lambda/${var.project}-db-migrations-lambda"
#   retention_in_days = 14
# }
#
# resource "aws_lambda_function" "migrations" {
#   function_name = "${var.project}-db-migrations-lambda"
#   role          = aws_iam_role.lambda_exec.arn
#
#   runtime = var.lambda_runtime
#   handler = "dist/migration.lambda.handler"
#
#   filename = "${path.module}/placeholder/placeholder.zip"
#
#   # Migracje bywają wolniejsze niż żądania HTTP. Limit 30 sekund z API Gateway
#   # tutaj nie obowiązuje, bo ta funkcja nie stoi za żadnym API.
#   memory_size = 512
#   timeout     = 300
#
#   vpc_config {
#     subnet_ids         = data.aws_subnets.default.ids
#     security_group_ids = [aws_security_group.lambda.id]
#   }
#
#   environment {
#     variables = {
#       NODE_ENV = "production"
#       DB_HOST  = aws_db_instance.postgres.address
#       DB_PORT  = tostring(aws_db_instance.postgres.port)
#       DB_NAME  = var.rds_database_name
#       DB_USER  = var.rds_username
#       DB_SSL   = "true"
#       # DB_PASSWORD ustawiane ręcznie, tak samo jak w Lambdzie API.
#     }
#   }
#
#   # ŻADNEGO aws_lambda_permission dla tej funkcji.
#   # Nie ma być wywoływalna przez API Gateway ani cokolwiek publicznego.
#
#   lifecycle {
#     ignore_changes = [filename, source_code_hash, s3_bucket, s3_key, environment]
#   }
# }
