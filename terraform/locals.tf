locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Log group Lambdy nazywa się zawsze według tego wzorca.
  api_log_group_name = "/aws/lambda/${var.api_lambda_function_name}"
}
