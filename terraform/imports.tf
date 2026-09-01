# ---------------------------------------------------------------------------
# BLOKI IMPORT
#
# Deklaratywna alternatywa dla komend terraform import. Zalety: trafiają do
# repozytorium, przechodzą code review, a terraform plan pokazuje skutki ZANIM
# cokolwiek dotknie stanu.
#
# JAK Z TEGO KORZYSTAĆ
#   1. Uzupełnij placeholdery poniżej prawdziwymi identyfikatorami
#      (gdzie ich szukać — IMPORT_PLAN.md).
#   2. Odkomentuj JEDNĄ sekcję.
#   3. terraform plan   — sprawdź, czy zasób zostanie zaimportowany bez zmian.
#   4. terraform apply  — wykonuje sam import (nie tworzy nic nowego).
#   5. Powtórz dla kolejnej sekcji, w kolejności z IMPORT_PLAN.md.
#
# Po zaimportowaniu wszystkiego bloki import można usunąć — swoje zrobiły.
#
# WSZYSTKO PONIŻEJ JEST ZAKOMENTOWANE I NIE ZOSTANIE WYKONANE.
# ---------------------------------------------------------------------------

# --- ETAP 1: fundamenty (nic od niczego nie zależy) ---

# import {
#   to = aws_iam_role.lambda_exec
#   id = "<LAMBDA_ROLE_NAME>"
# }
#
# import {
#   to = aws_iam_role_policy_attachment.lambda_basic
#   id = "<LAMBDA_ROLE_NAME>/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }
#
# import {
#   to = aws_iam_role_policy_attachment.lambda_vpc
#   id = "<LAMBDA_ROLE_NAME>/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
# }
#
# import {
#   to = aws_cloudwatch_log_group.api
#   id = "/aws/lambda/<LAMBDA_FUNCTION_NAME>"
# }

# --- ETAP 2: sieć (grupy i ich reguły) ---

# import {
#   to = aws_security_group.lambda
#   id = "<LAMBDA_SECURITY_GROUP_ID>"
# }
#
# import {
#   to = aws_security_group.rds
#   id = "<RDS_SECURITY_GROUP_ID>"
# }
#
# import {
#   to = aws_vpc_security_group_ingress_rule.rds_from_lambda
#   id = "<INGRESS_RULE_ID>"
# }
#
# import {
#   to = aws_vpc_security_group_egress_rule.lambda_all
#   id = "<LAMBDA_EGRESS_RULE_ID>"
# }
#
# import {
#   to = aws_vpc_security_group_egress_rule.rds_all
#   id = "<RDS_EGRESS_RULE_ID>"
# }

# --- ETAP 3: baza ---

# import {
#   to = aws_db_instance.postgres
#   id = "zoja-postgres"
# }

# --- ETAP 4: Lambda (zależy od roli i grup) ---

# import {
#   to = aws_lambda_function.api
#   id = "<LAMBDA_FUNCTION_NAME>"
# }

# --- ETAP 5: API Gateway (kolejność ma znaczenie) ---

# import {
#   to = aws_apigatewayv2_api.http
#   id = "<HTTP_API_ID>"
# }
#
# import {
#   to = aws_apigatewayv2_integration.lambda
#   id = "<HTTP_API_ID>/<INTEGRATION_ID>"
# }
#
# import {
#   to = aws_apigatewayv2_route.hello
#   id = "<HTTP_API_ID>/<ROUTE_ID>"
# }
#
# import {
#   to = aws_apigatewayv2_stage.default
#   id = "<HTTP_API_ID>/$default"
# }
#
# import {
#   to = aws_lambda_permission.api_gateway
#   id = "<LAMBDA_FUNCTION_NAME>/<STATEMENT_ID>"
# }

# --- ETAP 6: S3 (pięć osobnych zasobów, identyfikatorem jest nazwa bucketa) ---

# import {
#   to = aws_s3_bucket.frontend
#   id = "<FRONTEND_BUCKET_NAME>"
# }
#
# import {
#   to = aws_s3_bucket_public_access_block.frontend
#   id = "<FRONTEND_BUCKET_NAME>"
# }
#
# import {
#   to = aws_s3_bucket_ownership_controls.frontend
#   id = "<FRONTEND_BUCKET_NAME>"
# }
#
# import {
#   to = aws_s3_bucket_server_side_encryption_configuration.frontend
#   id = "<FRONTEND_BUCKET_NAME>"
# }
#
# import {
#   to = aws_s3_bucket_policy.frontend
#   id = "<FRONTEND_BUCKET_NAME>"
# }

# --- ETAP 7: CloudFront (na końcu — dotyka i S3, i API Gateway) ---

# import {
#   to = aws_cloudfront_origin_access_control.s3
#   id = "<OAC_ID>"
# }
#
# import {
#   to = aws_cloudfront_response_headers_policy.csp
#   id = "<RESPONSE_HEADERS_POLICY_ID>"
# }
#
# import {
#   to = aws_cloudfront_function.static_routing
#   id = "<CLOUDFRONT_FUNCTION_NAME>"
# }
#
# import {
#   to = aws_cloudfront_distribution.main
#   id = "<DISTRIBUTION_ID>"
# }
