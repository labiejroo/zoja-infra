# ---------------------------------------------------------------------------
# IAM — ISTNIEJE, DO IMPORTU
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = var.lambda_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Logi do CloudWatch.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Tworzenie i zarządzanie ENI w VPC — bez tego Lambda nie wystartuje w sieci.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# NA PRZYSZŁOŚĆ
# Gdy hasło do bazy przeniesiemy do SSM Parameter Store, dojdzie tu polityka
# z ssm:GetParameter na KONKRETNY ARN parametru oraz kms:Decrypt na konkretny
# klucz. Nigdy ssm:* ani Resource "*".
#
# Pamiętaj przy tym, że bez Interface VPC Endpointu dla SSM prywatna Lambda
# i tak nie dosięgnie tej usługi — sama polityka IAM nie wystarczy.
