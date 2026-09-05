# Wartości przydatne po imporcie — do wklejenia w konfigurację CI i frontendu.
# Żaden z outputów nie ujawnia sekretów.

output "cloudfront_domain_name" {
  description = "Adres dystrybucji. To jest URL, który wpisujesz w iframe na Netlify."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "Potrzebny do invalidacji cache w CI frontendu."
  value       = aws_cloudfront_distribution.main.id
}

output "frontend_bucket_name" {
  description = "Cel aws s3 sync w CI frontendu."
  value       = aws_s3_bucket.frontend.id
}

output "http_api_endpoint" {
  description = "Bezpośredni endpoint API Gateway. Do diagnostyki — ruch produkcyjny idzie przez CloudFront."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "api_lambda_function_name" {
  description = "Cel aws lambda update-function-code w CI backendu."
  value       = aws_lambda_function.api.function_name
}

output "rds_endpoint" {
  description = "Host bazy — wartość dla zmiennej DB_HOST w Lambdzie."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Port bazy — wartość dla zmiennej DB_PORT."
  value       = aws_db_instance.postgres.port
}

output "mail_lambda_function_name" {
  description = "Cel aws lambda update-function-code dla Mail Lambdy — ten sam artefakt ZIP, inny handler."
  value       = aws_lambda_function.mail.function_name
}
