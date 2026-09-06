# ---------------------------------------------------------------------------
# LOGOWANIE DO PANELU GOSPODARZY
#
# PROBLEM, KTÓRY TO ROZWIĄZUJE
# Do tej pory /api/admin/* było otwarte dla każdego, kto znał adres. Parametr
# ?zoja nigdy nie był zabezpieczeniem — przełącza tylko to, co widać na
# ekranie. Odkąd w bazie leżą prawdziwe adresy gości i idą do nich maile,
# otwarty panel przestał być akceptowalnym długiem.
#
# CO TU JEST, A CZEGO NIE MA
# Terraform tworzy wyłącznie POJEMNIK na sekret i uprawnienie do jego odczytu.
# Wartości nie dotyka — tak samo jak przy zoja/database.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. SEKRET — SAM POJEMNIK, BEZ ZAWARTOŚCI
#
# ŚWIADOMIE BEZ aws_secretsmanager_secret_version.
#
# Gdyby hash hasła i klucz podpisu sesji trafiły do Terraforma, wylądowałyby
# jawnym tekstem w terraform.tfstate — czyli w pliku, który leży na dysku
# laptopa i którego nie chronimy niczym poza .gitignore. Wartość wgrywamy raz,
# ręcznie, przez AWS CLI, dokładnie jak hasło do bazy.
#
# Oczekiwany kształt (generuje go scripts/generate-admin-auth-secret.mjs):
#
#   {"passwordHash":"scrypt-v1$<sól>$<hash>","sessionSecret":"<base64url>"}
#
# HASŁA JAWNEGO NIE MA TAM NIGDY — ani w Terraformie, ani w Secrets Managerze.
#
# OSOBNY SEKRET OD zoja/database, bo uprawnienie nadaje się na ARN. Wspólny
# dokument oznaczałby, że kod potrzebujący hasła do bazy dostaje przy okazji
# hasło do panelu.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "admin_auth" {
  name        = local.admin_auth_secret_name
  description = "Hash hasla i klucz podpisu sesji panelu gospodarzy. Wartosc ustawiana poza Terraformem."

  recovery_window_in_days = 7
}


# ---------------------------------------------------------------------------
# 2. UPRAWNIENIE — ODCZYT JEDNEGO KONKRETNEGO SEKRETU
#
# Osobna polityka, a nie dopisanie ARN-u do istniejącej lambda_secrets. Dwie
# polityki czyta się jako dwa zdania („czytaj sekret bazy", „czytaj sekret
# logowania"), a odebranie jednego uprawnienia sprowadza się do odpięcia jednej
# polityki, zamiast do edytowania dokumentu, z którego korzysta coś jeszcze.
#
# UWAGA — ŚWIADOMY DŁUG:
# tę rolę współdzieli Lambda migracyjna, więc formalnie zyskuje ona możliwość
# odczytania sekretu logowania. Nie rozdzielamy ról przy wdrażaniu auth, bo to
# oznaczałoby zmianę działającej funkcji produkcyjnej przy okazji etapu
# o czymś innym. Kod migracji tego sekretu nie czyta.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_admin_auth" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.admin_auth.arn]
  }
}

resource "aws_iam_policy" "lambda_admin_auth" {
  name        = "${local.name_prefix}-lambda-admin-auth-read"
  path        = "/service-role/"
  description = "Read-only access to the Zoja admin auth secret"

  policy = data.aws_iam_policy_document.lambda_admin_auth.json
}

resource "aws_iam_role_policy_attachment" "lambda_admin_auth" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_admin_auth.arn
}


# ---------------------------------------------------------------------------
# 3. DROGA SIECIOWA — JUŻ ISTNIEJE
#
# Lambda API sięga do Secrets Managera przez Interface VPC Endpoint utworzony
# przy okazji hasła do bazy (aws_vpc_endpoint.secretsmanager). Endpoint dotyczy
# USŁUGI, nie pojedynczego sekretu, więc drugi byłby czystym marnotrawstwem:
# ok. 8 USD miesięcznie za dokładnie tę samą trasę.
#
# Nowych zasobów sieciowych ten plik nie tworzy.
# ---------------------------------------------------------------------------
