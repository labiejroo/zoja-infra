provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront jest usługą globalną, ale certyfikaty ACM dla niej muszą powstawać
# w us-east-1. Dziś jedziemy na domyślnym certyfikacie *.cloudfront.net, więc ten
# provider nie jest jeszcze używany — jest tu po to, żeby dodanie własnej domeny
# nie wymagało przepisywania konfiguracji.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
