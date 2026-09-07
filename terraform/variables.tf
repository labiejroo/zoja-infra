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
  description = "Nazwa istniejącej Lambdy obsługującej API."
  type        = string
  default     = "zoja-hello-api-lambda-central"
}

variable "lambda_execution_role_name" {
  description = "Nazwa istniejącej roli wykonawczej Lambdy."
  type        = string
  default     = "zoja-hello-api-lambda-central-role-fz8vv09h"
}

variable "frontend_bucket_name" {
  description = "Nazwa bucketa S3 z frontendem."
  type        = string
  default     = "zoja-aws-lab-frontend-631245465107-eu-central-1-an"
}

variable "cloudfront_function_name" {
  description = "Nazwa CloudFront Function routującej trasy statyczne."
  type        = string
  default     = "zoja-static-routing"
}

variable "rds_identifier" {
  description = "Identyfikator instancji RDS."
  type        = string
  default     = "zoja-postgres"
}

variable "rds_database_name" {
  description = "Nazwa początkowej bazy w RDS."
  type        = string
  default     = "zojaDB"
}

variable "rds_username" {
  description = "Master username RDS."
  type        = string
  default     = "postgres"
}

variable "rds_instance_class" {
  description = "Klasa instancji RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_engine_version" {
  description = <<-EOT
    Wersja PostgreSQL — odczytana z konsoli.
    Przy włączonym auto minor upgrade wersja potrafi się zmienić sama, co przy
    zbyt szczegółowej wartości daje wieczny dryf w planie. Rozważ podanie samej
    wersji major (np. "16") i pozostawienie reszty AWS-owi.
  EOT
  type        = string
  default     = "18.3"
}

variable "lambda_runtime" {
  description = "Runtime Lambdy. Potwierdzone w konsoli: Node.js 24."
  type        = string
  default     = "nodejs24.x"
}

variable "parent_site_origin" {
  description = <<-EOT
    Origin strony nadrzędnej osadzającej aplikację w iframe — trafia do
    frame-ancestors w Response Headers Policy.
  EOT
  type        = string
  default     = "https://przywitajzoje.netlify.app"
}

# ---------------------------------------------------------------------------
# WYSYŁKA MAILI (ETAP EMAIL B1)
#
# Wszystkie mają puste wartości domyślne i to jest celowe: infrastruktura ma
# dać się zaplanować i utworzyć, ZANIM znamy adresy. Pusty adres nadawcy
# oznacza po prostu, że Mail Lambda istnieje, ale nie jest gotowa do wysyłki —
# co jest w porządku, dopóki EMAIL_ENABLED pozostaje "false".
# ---------------------------------------------------------------------------


variable "email_enabled" {
  description = <<-EOT
    Czy backend ma faktycznie wysyłać maile.

    Trafia do Lambdy API jako EMAIL_ENABLED. Przy false MailDispatcherService
    przy każdym zdarzeniu wychodzi wcześniej i nie dotyka SDK — Mail Lambda
    nie jest wywoływana ani razu.

    DEFAULT MUSI ZOSTAĆ false. Zmienna istnieje po to, żeby włączenie wysyłki
    było świadomym terraform plan/apply z zapisem w repozytorium, a nie
    kliknięciem w konsoli AWS, po którym nikt nie pamięta, kiedy i dlaczego.
  EOT
  type        = bool
  default     = false
}

variable "ses_from_email" {
  description = <<-EOT
    Adres nadawcy dla SES. Puste = nie tworzymy żadnej tożsamości SES i nie
    nadajemy Mail Lambdzie uprawnienia ses:SendEmail.
  EOT
  type        = string
  default     = ""
}

variable "parent_notification_emails" {
  description = <<-EOT
    Skrzynki rodziców, na które idzie prośba o decyzję. Do Lambdy trafiają
    jako jeden string rozdzielony przecinkami — zmienne środowiskowe Lambdy
    nie mają typu listy.
  EOT
  type        = list(string)
  default     = []
}

variable "ses_test_recipient_emails" {
  description = <<-EOT
    Adresy do zweryfikowania na czas testu w piaskownicy SES. W sandboksie SES
    wysyła WYŁĄCZNIE na zweryfikowane adresy, więc bez tego pierwszy test
    odbije się o MessageRejected. Pusta lista = zero tożsamości.
  EOT
  type        = list(string)
  default     = []
}

variable "action_page_url" {
  description = <<-EOT
    Adres strony decyzyjnej wstawiany w linki w mailu. Puste = wyliczamy go
    z domeny CloudFrontu.

    BEZ FRAGMENTU. Część po # dokłada szablon maila, doklejając tam token
    decyzji. Fragment podany tutaj zostałby zjedzony przez ten doklejony.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = !strcontains(var.action_page_url, "#")
    error_message = "action_page_url nie moze zawierac fragmentu (#) - dokleja go szablon maila razem z tokenem."
  }
}

variable "turnstile_enabled" {
  description = <<-EOT
    Czy publiczny formularz ma wymagać rozwiązanego wyzwania Turnstile.

    Trafia do Lambdy API jako TURNSTILE_ENABLED. Przy false TurnstileService
    przy każdym żądaniu wychodzi wcześniej i weryfikator nie jest wywoływany
    ani razu — formularz działa dokładnie jak przed tym etapem.

    DEFAULT MUSI ZOSTAĆ false. Włączenie wymaga wcześniej widgetu w Cloudflare,
    klucza prywatnego w zoja/turnstile i frontendu z sitekey na produkcji.
    Odwrotna kolejność zablokowałaby formularz wszystkim gościom.

    Zmienna zostaje na stałe także po wdrożeniu: jest wyłącznikiem awaryjnym
    na wypadek dłuższej awarii Cloudflare.
  EOT
  type        = bool
  default     = false
}
