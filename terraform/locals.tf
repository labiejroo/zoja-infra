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
}
