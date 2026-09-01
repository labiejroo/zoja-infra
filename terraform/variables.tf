variable "aws_region" {
  description = "Region, w którym stoi cała infrastruktura."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Prefiks nazw i tagów."
  type        = string
  default     = "zoja"
}

variable "environment" {
  description = "Środowisko. Na razie jedno."
  type        = string
  default     = "prod"
}

# ---------------------------------------------------------------------------
# NAZWY I IDENTYFIKATORY ISTNIEJĄCYCH ZASOBÓW
#
# Wszystkie te zasoby zostały utworzone ręcznie w konsoli AWS. Terraform ma je
# tylko przejąć, nie tworzyć od nowa. Wartości domyślne są PLACEHOLDERAMI —
# podmień je przed importem. Gdzie ich szukać, opisuje IMPORT_PLAN.md.
# ---------------------------------------------------------------------------

variable "api_lambda_function_name" {
  description = "Nazwa istniejącej Lambdy obsługującej API. TODO: uzupełnij."
  type        = string
  default     = "TODO_LAMBDA_FUNCTION_NAME"
}

variable "lambda_execution_role_name" {
  description = "Nazwa istniejącej roli wykonawczej Lambdy. TODO: uzupełnij."
  type        = string
  default     = "TODO_LAMBDA_ROLE_NAME"
}

variable "frontend_bucket_name" {
  description = "Nazwa bucketa S3 z frontendem. TODO: uzupełnij."
  type        = string
  default     = "TODO_FRONTEND_BUCKET_NAME"
}

variable "cloudfront_function_name" {
  description = "Nazwa CloudFront Function routującej trasy statyczne. TODO: uzupełnij."
  type        = string
  default     = "TODO_CLOUDFRONT_FUNCTION_NAME"
}

variable "rds_identifier" {
  description = "Identyfikator instancji RDS."
  type        = string
  default     = "zoja-postgres"
}

variable "rds_database_name" {
  description = "Nazwa początkowej bazy w RDS."
  type        = string
  default     = "zoja"
}

variable "rds_username" {
  description = "Master username RDS. TODO: uzupełnij zgodnie z tym, co ustawiono ręcznie."
  type        = string
  default     = "TODO_RDS_MASTER_USERNAME"
}

variable "rds_instance_class" {
  description = "Klasa instancji RDS. TODO: sprawdź w konsoli i dopasuj."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_engine_version" {
  description = <<-EOT
    Wersja PostgreSQL. TODO: wpisz DOKŁADNIE tę z konsoli.
    Przy włączonym auto minor upgrade wersja potrafi się zmienić sama, co przy
    zbyt szczegółowej wartości daje wieczny dryf w planie. Rozważ podanie samej
    wersji major (np. "16") i pozostawienie reszty AWS-owi.
  EOT
  type        = string
  default     = "TODO_RDS_ENGINE_VERSION"
}

variable "lambda_runtime" {
  description = "Runtime Lambdy. Potwierdzone w konsoli: Node.js 24."
  type        = string
  default     = "nodejs24.x"
}

variable "parent_site_origin" {
  description = <<-EOT
    Origin strony nadrzędnej osadzającej aplikację w iframe — trafia do
    frame-ancestors w Response Headers Policy. TODO: uzupełnij adresem Netlify.
  EOT
  type        = string
  default     = "https://TODO.netlify.app"
}
