# ---------------------------------------------------------------------------
# SES — TOŻSAMOŚCI, WYŁĄCZNIE GDY PODAMY ADRESY
#
# STAN KONTA NA DZIŚ (odczytany, nie zgadnięty):
#
#   ProductionAccessEnabled = false   <- PIASKOWNICA
#   SendingEnabled          = true
#   EnforcementStatus       = HEALTHY
#   tożsamości              = brak
#
# Co z tego wynika praktycznie: w piaskownicy SES wysyła TYLKO na adresy
# zweryfikowane. Przy zerze tożsamości nie wyjdzie ani jeden mail — także do
# rodziców. Dlatego ten plik nie tworzy dziś niczego: przy pustych zmiennych
# for_each dostaje pusty zbiór i liczba zasobów wynosi zero.
#
# CZEGO TU NIE MA I DLACZEGO
# Nie ma zarządzania Production Access. To nie jest zasób w AWS, tylko wniosek
# rozpatrywany przez człowieka po stronie AWS-a — provider nie ma dla tego
# odpowiednika i nie da się tego wyrazić w Terraformie.
#
# CHECKPOINT PRZED PRAWDZIWYM RUCHEM (kolejność ma znaczenie):
#
#   1. ses_from_email        — zweryfikowany adres albo domena nadawcy
#   2. wniosek o Production Access — bez niego maile do GOŚCI nie wyjdą,
#      bo adresu gościa nie da się zweryfikować z góry
#   3. EMAIL_ENABLED = "true" — dopiero po świadomym zatwierdzeniu, osobno
#   4. autoryzacja /api/admin/* — te trasy są dziś zupełnie otwarte, więc do
#      bazy nie wolno wpuścić prawdziwych danych osobowych, a maile oznaczają
#      właśnie prawdziwe adresy
# ---------------------------------------------------------------------------

resource "aws_sesv2_email_identity" "verified" {
  for_each = local.ses_identities

  email_identity = each.value

  # Tożsamość adresowa (a nie domenowa) weryfikuje się mailem z linkiem, który
  # AWS wysyła na ten adres. Terraform utworzy zasób od razu, ale pozostanie on
  # w stanie PENDING, dopóki ktoś nie kliknie w link ze skrzynki.
}
