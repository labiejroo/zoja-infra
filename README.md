# zoja-infra

Infrastruktura AWS aplikacji „Odwiedziny u Zoi", opisana w Terraformie.

> ## Przeczytaj to najpierw
>
> **Cała infrastruktura już istnieje.** Powstała ręcznie w konsoli AWS i działa.
> Terraform ma ją dopiero **przejąć przez import**, a nie tworzyć od nowa.
>
> `terraform apply` na nieuzupełnionej konfiguracji spróbuje **stworzyć
> duplikaty** — drugą bazę, drugą dystrybucję, drugi bucket. Zanim uruchomisz
> cokolwiek poza `fmt`, `init` i `validate`, przeczytaj
> [`IMPORT_PLAN.md`](./IMPORT_PLAN.md).

## Stan na dziś

| Krok | Stan |
| --- | --- |
| `terraform fmt` | wykonany |
| `terraform init` | wykonany (Terraform 1.15.8, provider AWS ~> 6.0) |
| `terraform validate` | przechodzi |
| `terraform plan` | **nie wykonywany** |
| `terraform import` | **nie wykonywany** |
| `terraform apply` | **nie wykonywany** |

Żaden zasób w AWS nie został dotknięty. Placeholdery nie są uzupełnione —
identyfikatorów nie zgadywałem.

## Co jest już w AWS

Region: **eu-central-1**.

```
CloudFront (xxxx.cloudfront.net)
├── behavior "*"       → S3 (prywatny, OAC) → statyczny frontend Next.js
│   └── CloudFront Function: /admin → /admin.html
│   └── Response Headers Policy: CSP frame-ancestors
└── behavior "/api/*"  → API Gateway HTTP API → Lambda
                                                  │
                          Default VPC             │
                          zoja-lambda-sg ─────────┘
                                 │ TCP 5432
                                 ▼
                          zoja-rds-sg → RDS PostgreSQL "zoja-postgres"
                                        (prywatny, bez publicznego dostępu)
```

Potwierdzone testem z Lambdy przez `node:net`: DNS, routing VPC, podsieci, ENI,
grupy bezpieczeństwa i port 5432 działają.

## Czego NIE tworzyć drugi raz

Wszystko z listy poniżej istnieje. Każda pozycja ma odpowiednik w `terraform/`
przygotowany **do importu**, nie do utworzenia.

- bucket S3 z frontendem (plus cztery zasoby poboczne: polityka, blokada
  dostępu publicznego, szyfrowanie, własność obiektów)
- dystrybucja CloudFront, OAC, Response Headers Policy, CloudFront Function
- HTTP API, integracja z Lambdą, trasa `ANY /api/{proxy+}`, stage `$default`
- Lambda API, jej rola wykonawcza, dwa attachmenty polityk, log group
- RDS `zoja-postgres`
- grupy `zoja-lambda-sg` i `zoja-rds-sg` wraz z regułami

Default VPC i podsieci wchodzą przez `data` — Terraform je czyta, nigdy nie zmienia.

## Struktura

```
terraform/
  versions.tf              wymagane wersje (Terraform >= 1.5 dla bloków import)
  providers.tf             eu-central-1 + alias us-east-1 pod przyszły certyfikat
  backend.tf               stan lokalny + instrukcja przejścia na S3
  variables.tf             placeholdery istniejących zasobów, każdy z TODO
  locals.tf
  outputs.tf               wartości dla CI frontendu i backendu

  networking.tf            data: Default VPC i podsieci — tylko odczyt
  security-groups.tf       obie grupy i ich reguły
  rds.tf                   zoja-postgres, bez hasła

  iam.tf                   rola wykonawcza Lambdy
  lambda.tf                Lambda API + log group
  lambda-migrations.tf     przyszła Lambda migracyjna — CAŁY plik zakomentowany
  api-gateway.tf           HTTP API; trasy catch-all zakomentowane

  s3.tf                    bucket + cztery zasoby poboczne
  cloudfront.tf            dystrybucja, OAC, Response Headers Policy
  cloudfront-functions.tf  CloudFront Function
  functions/
    static-routing.js      kod funkcji jako plik, nie heredoc w HCL

  imports.tf               bloki import, etapami, zakomentowane
```

Bez modułów. Projekt jest mały, a czytelność ważniejsza niż abstrakcja.

## Uruchomienie

```bash
cd terraform
terraform fmt -recursive
terraform init
terraform validate
```

Te trzy polecenia są bezpieczne i **nie wymagają poświadczeń AWS** — nie
kontaktują się z kontem. Wszystko dalej (`plan`, `import`, `apply`) wymaga
uwierzytelnienia i jest opisane w [`IMPORT_PLAN.md`](./IMPORT_PLAN.md).

Poświadczenia: **AWS CLI z SSO**, nie stałe klucze dostępu.

```bash
aws sso login --profile AdministratorAccess-631245465107
export AWS_PROFILE=AdministratorAccess-631245465107
# PowerShell: $env:AWS_PROFILE = "AdministratorAccess-631245465107"
```

## Podział odpowiedzialności

Ta granica jest celowa i warto jej pilnować.

| | Terraform | CI aplikacji |
| --- | --- | --- |
| Bucket S3 | tworzy i konfiguruje | — |
| Pliki frontendu w buckecie | **nie dotyka** | `aws s3 sync` + invalidacja |
| Funkcja Lambda | konfiguracja: rola, sieć, pamięć, timeout, zmienne środowiskowe **poza `DB_PASSWORD`** | — |
| Kod Lambdy | **nie dotyka** | `aws lambda update-function-code` |
| API Gateway, RDS, IAM, CloudFront | tworzy i konfiguruje | — |

Dzięki temu **zmiana kodu nigdy nie wymaga `terraform apply`**. Realizują to
bloki `ignore_changes` na atrybutach artefaktu Lambdy — bez nich każdy deploy
backendu pokazywałby dryf w planie.

## Sekrety

`DB_PASSWORD` **nie występuje w tym repozytorium** i nie ma go tu być.

Na czas laba jest ustawiane ręcznie jako zmienna środowiskowa Lambdy w konsoli.
W `lambda.tf` w `ignore_changes` jest **tylko ten jeden klucz**:

```hcl
environment[0].variables["DB_PASSWORD"]
```

Pozostałe zmienne — `NODE_ENV`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
`DB_SSL` — zarządza Terraform. Wcześniej ignorowany był cały blok `environment`
i przez to `DB_SSL` trzeba było dokładać ręcznie w konsoli.

Dlaczego to bezpieczne, mimo że `UpdateFunctionConfiguration` nadpisuje mapę
`Variables` w całości: `ignore_changes` nie znaczy „nie wysyłaj tego pola", tylko
„weź dla tej ścieżki wartość ze stanu". Terraform wysyła więc pełną mapę razem
z hasłem odczytanym przy refreshu. Skutek uboczny wart zapamiętania — rotacja
hasła zrobiona w konsoli nie zostanie cofnięta przez następny apply.

Master password RDS też nie jest zarządzane: AWS nigdy nie zwraca go przez API,
więc import go nie wypełni. Atrybut `password` jest pominięty w konfiguracji
i wpisany w `ignore_changes`. Rotacja odbywa się poza Terraformem.

Plik stanu (`*.tfstate`) zawiera atrybuty zasobów w postaci jawnej i jest
w `.gitignore`. Nie commituj go.

### Dlaczego nie SSM Parameter Store

Lambda stoi w VPC bez NAT Gateway, więc nie ma trasy do publicznych endpointów
AWS. Sięgnięcie po SSM albo Secrets Manager wymagałoby najpierw **Interface VPC
Endpointu** dla tej usługi. Zmienne środowiskowe wstrzykuje sama usługa Lambda,
zanim kod ruszy — bez ruchu sieciowego. Docelowe rozwiązanie projektujemy osobno.

## Przyszła Lambda migracyjna

`zoja-db-migrations-lambda` **jeszcze nie istnieje**, więc nie podlega importowi.
Konfiguracja czeka zakomentowana w `lambda-migrations.tf` i powstanie dopiero
świadomym `apply`.

Zasada: ten sam artefakt ZIP co API, inny handler
(`dist/migration.lambda.handler`), ta sama VPC i grupa bezpieczeństwa,
**bez wyzwalacza API Gateway**. Uruchamiana ręcznie:

```bash
aws lambda invoke --function-name zoja-db-migrations-lambda response.json
```

Dzięki temu migrujemy prywatną bazę, nie otwierając jej na świat i nie
wystawiając publicznego `/api/migrate`.

## GitHub Actions — przygotowanie

Workflow jeszcze nie ma. Docelowy podział:

| Repozytorium | Po `git push` |
| --- | --- |
| `zoja-frontend` | build → `aws s3 sync out/` → invalidacja CloudFront |
| `zoja-backend` | testy → build → `package:lambda` → `update-function-code` |
| `zoja-infra` | `fmt -check` → `validate` → `plan` → apply za zgodą |

Uwierzytelnianie: **OIDC + rola IAM**, nigdy długowieczne klucze w sekretach
repozytorium. Rola potrzebuje polityki zaufania do `token.actions.githubusercontent.com`
z warunkiem na `sub` ograniczonym do konkretnego repozytorium i gałęzi.

Wartości potrzebne workflowom są w `outputs.tf`: nazwa bucketa, identyfikator
dystrybucji, nazwa funkcji Lambdy.

## Zabezpieczenia

`prevent_destroy = true` mają: instancja RDS, bucket frontendu, dystrybucja
CloudFront i log group Lambdy. `terraform destroy` odmówi ich usunięcia, dopóki
ktoś świadomie nie zdejmie flagi.

## TODO

- [ ] Uzupełnić placeholdery w `variables.tf` (każdy ma komentarz `TODO`).
- [x] Przeprowadzić import etapami według `IMPORT_PLAN.md`.
- [x] Dojść do `plan` bez zmian.
- [x] Trasa catch-all `ANY /api/{proxy+}` (dawne `GET /api/hello`).
- [ ] Dodać trasę `ANY /api` (`api_root`), gdy będzie potrzebna.
- [ ] Ustalić i włączyć `reserved_concurrent_executions` na Lambdzie API.
- [ ] Utworzyć `zoja-db-migrations-lambda`.
- [ ] Przenieść stan do S3 (`backend.tf` ma gotową instrukcję).
- [ ] Dodać workflow GitHub Actions z OIDC.
