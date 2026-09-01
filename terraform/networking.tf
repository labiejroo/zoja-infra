# ---------------------------------------------------------------------------
# SIEĆ — WYŁĄCZNIE DO ODCZYTU
#
# Lambda i RDS stoją w Default VPC konta. Terraform ma o niej wiedzieć, ale
# nie ma prawa jej dotknąć, dlatego używamy data source, a NIE zasobu
# `aws_default_vpc`. Ten drugi adoptuje domyślną VPC do stanu i potrafi ją
# modyfikować — czego przy działającej produkcji zdecydowanie nie chcemy.
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# UWAGA: Lambda nie ma NAT Gateway, więc nie wychodzi do publicznego internetu.
# Do RDS w tej samej VPC dociera bez problemu, a logi do CloudWatch wysyła
# usługa Lambda w jej imieniu — nie kod przez ENI. Gdyby kiedyś potrzebny był
# dostęp do SSM albo Secrets Manager, właściwą odpowiedzią jest Interface VPC
# Endpoint dla konkretnej usługi, a nie NAT Gateway z opłatą godzinową.
