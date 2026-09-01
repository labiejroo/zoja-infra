# STAN TERRAFORMA
#
# Na tym etapie stan jest LOKALNY (plik terraform.tfstate obok konfiguracji).
# To wystarcza dla jednej osoby i nie wymaga tworzenia niczego w AWS.
#
# Plik stanu zawiera atrybuty zasobów w postaci jawnej i jest w .gitignore.
# Nie commituj go.
#
# Przejście na stan zdalny (gdy dojdzie CI/CD albo druga osoba):
#
#   1. Utwórz bucket S3 na stan, z wersjonowaniem i szyfrowaniem.
#   2. Odkomentuj blok poniżej i uzupełnij nazwę bucketa.
#   3. Uruchom `terraform init -migrate-state`.
#
# Blokada stanu w S3 działa natywnie od AWS provider v6 (use_lockfile),
# więc osobna tabela DynamoDB nie jest już potrzebna.
#
# terraform {
#   backend "s3" {
#     bucket       = "<STATE_BUCKET_NAME>" # TODO
#     key          = "zoja/terraform.tfstate"
#     region       = "eu-central-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
