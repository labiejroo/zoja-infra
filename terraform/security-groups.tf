# ---------------------------------------------------------------------------
# GRUPY BEZPIECZEŃSTWA — ISTNIEJĄ, DO IMPORTU
# ---------------------------------------------------------------------------

resource "aws_security_group" "lambda" {
  name   = "zoja-lambda-sg"
  vpc_id = data.aws_vpc.default.id

  description = "Security group for Zoja API Lambda"

  # Opisu grupy nie da się zmienić po utworzeniu. Jeśli po imporcie plan chce go
  # zmodyfikować, to znaczy, że wartość wyżej nie zgadza się z rzeczywistością —
  # popraw ją tutaj, nie w AWS.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_security_group" "rds" {
  name   = "zoja-rds-sg"
  vpc_id = data.aws_vpc.default.id

  description = "Created by RDS management console"

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Reguły jako osobne zasoby — to obecnie zalecana forma. Każda ma własny
# identyfikator sgr-… i importuje się niezależnie od samej grupy.
resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
}

# Domyślna reguła wyjściowa "wszystko dozwolone" istnieje na obu grupach,
# bo AWS tworzy ją automatycznie. Też ma swój identyfikator i też podlega
# importowi — patrz IMPORT_PLAN.md.
resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
