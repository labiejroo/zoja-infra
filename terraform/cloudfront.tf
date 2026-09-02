# ---------------------------------------------------------------------------
# CLOUDFRONT — ISTNIEJE, DO IMPORTU
#
# TO JEST NAJTRUDNIEJSZY IMPORT W CAŁYM ZESTAWIE.
# Dystrybucja ma kilkadziesiąt pól, a różnice w kolejności behaviorów albo
# w wartościach domyślnych potrafią generować pozorny dryf. Najszybsza droga
# opisana w IMPORT_PLAN.md: zaimportować, wygenerować konfigurację przez
# terraform plan -generate-config-out i dopiero potem posprzątać ręcznie.
#
# Wartości poniżej to SZKIELET oparty na przekazanym opisie architektury.
# Traktuj je jako punkt wyjścia do uzgodnienia z rzeczywistością, nie jako
# gotowy stan.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "oac-zoja-aws-lab-frontend-631245465107-eu-central-1--mtfxvk1dg23"
  description                       = "Created by CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "csp" {
  name    = "ZojamyResponsePolicy"
  comment = ""

  security_headers_config {
    # To JEDYNE miejsce, w którym frame-ancestors istnieje na produkcji.
    # W Next.js z output "export" funkcja headers() nie działa — nie ma serwera,
    # który mógłby ją wykonać.
    content_security_policy {
      content_security_policy = "frame-ancestors ${var.parent_site_origin};"
      override                = true
    }

    # X-Frame-Options CELOWO pominięte: zna tylko DENY i SAMEORIGIN, więc
    # kolidowałoby z osadzeniem na stronie nadrzędnej. Rolę pełni frame-ancestors.
  }
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = ""
  comment             = ""

  # --- ORIGIN 1: S3 z frontendem, przez OAC ---
  origin {
    origin_id                = "zoja-aws-lab-frontend-631245465107-eu-central-1-an.s3.eu-central-1.amazonaws.com-mtfxh29vx1g"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id

    response_completion_timeout = 0
  }

  # --- ORIGIN 2: API Gateway ---
  origin {
    origin_id = "zoja-api-gateway-origin"
    # Host bez schematu i bez ścieżki — sam human-readable endpoint HTTP API.
    domain_name = replace(aws_apigatewayv2_api.http.api_endpoint, "https://", "")

    response_completion_timeout = 0

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      ip_address_type        = "ipv4"
    }
  }

  # --- DEFAULT: wszystko inne idzie do S3 ---
  default_cache_behavior {
    target_origin_id       = "zoja-aws-lab-frontend-631245465107-eu-central-1-an.s3.eu-central-1.amazonaws.com-mtfxh29vx1g"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
    ]

    cached_methods = [
      "GET",
      "HEAD",
    ]

    compress = true

    # Managed-CachingOptimized
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.csp.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.static_routing.arn
    }
  }

  # --- /api/*: do API Gateway, bez cache ---
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "zoja-api-gateway-origin"
    viewer_protocol_policy = "redirect-to-https"

    # Backend musi móc przyjąć każdą metodę, nie tylko GET.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    # Managed-CachingDisabled. Cache na tej ścieżce byłby wyciekiem danych:
    # odpowiedź jednego zalogowanego użytkownika trafiłaby do następnego.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Managed-AllViewerExceptHostHeader. Host MUSI zostać hostem API Gateway,
    # inaczej brama nie rozpozna żądania — dlatego nie AllViewer.
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

    # ŻADNEJ function_association: funkcja routingu dotyczy plików statycznych
    # i nie ma nic do roboty na ścieżce API.
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Domyślny certyfikat *.cloudfront.net — bez własnej domeny nic nie płacimy.
    # Po dodaniu domeny: acm_certificate_arn (z us-east-1) + aliases + SNI.
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "zojaDistributonCloudFront"
  }

  lifecycle {
    prevent_destroy = true
  }
}
