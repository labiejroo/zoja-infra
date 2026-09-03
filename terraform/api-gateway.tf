# ---------------------------------------------------------------------------
# API GATEWAY HTTP API — ISTNIEJE, DO IMPORTU
#
# ŚCIEŻKI
# Stage nazywa się $default, a HTTP API w tym trybie NIE dokleja nazwy stage
# do ścieżki (inaczej niż REST API). CloudFront przekazuje /api/health bez
# zmian, API Gateway podaje w rawPath dokładnie /api/health, a NestJS
# z globalnym prefiksem "api" właśnie tego oczekuje. Gdyby stage miał nazwę,
# w ścieżce pojawiłoby się /nazwa/api/health i wszystko wracałoby 404.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "http" {
  name          = "zoja-gateway-central"
  protocol_type = "HTTP"

  # CORS celowo nieustawiony: przeglądarka woła /api/* na tym samym originie
  # co frontend (CloudFront), więc żądania nie są cross-origin i preflight
  # nie występuje. Włączenie CORS tutaj byłoby myleniem tropów.
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id = aws_apigatewayv2_api.http.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# TRASA TESTOWA — istnieje dziś i podlega importowi.
resource "aws_apigatewayv2_route" "hello" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# TRASY CATCH-ALL DLA NESTA — JESZCZE NIE ISTNIEJĄ.
#
# NestJS sam routuje żądania, więc API Gateway ma tylko przekazać mu wszystko
# spod /api. Potrzebne są dwie trasy: jedna na goły /api, druga na resztę.
# Po ich dodaniu trasę GET /api/hello można usunąć — obsłuży ją catch-all.
#
# Odkomentuj świadomie: to jedyny fragment tego pliku, który coś TWORZY.
#
# resource "aws_apigatewayv2_route" "api_root" {
#   api_id    = aws_apigatewayv2_api.http.id
#   route_key = "ANY /api"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }
#
# resource "aws_apigatewayv2_route" "api_proxy" {
#   api_id    = aws_apigatewayv2_api.http.id
#   route_key = "ANY /api/{proxy+}"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
# }

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  # TODO: jeśli w konsoli włączono access logging, dopisz tu blok
  # access_log_settings z ARN-em log group i formatem — inaczej plan
  # będzie chciał je wyłączyć.
}
