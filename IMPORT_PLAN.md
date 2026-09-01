# Plan importu istniejącej infrastruktury

Wszystkie zasoby opisane w `terraform/` **już istnieją w AWS** i powstały ręcznie
w konsoli. Terraform ma je przejąć, a nie stworzyć od nowa.

> **Zanim cokolwiek uruchomisz:** `terraform apply` na nieuzupełnionej
> konfiguracji spróbuje **utworzyć duplikaty** wszystkich zasobów. Kolejność
> kroków w tym dokumencie nie jest kosmetyczna.

## Stan na dziś

| | |
| --- | --- |
| `terraform fmt` | wykonany |
| `terraform init` | wykonany, providery pobrane |
| `terraform validate` | przechodzi |
| `terraform plan` | **nie wykonywany** — wymaga poświadczeń AWS |
| `terraform import` | **nie wykonywany** |
| `terraform apply` | **nie wykonywany** |

Placeholdery w `variables.tf` i `imports.tf` **nie są uzupełnione**. Nie
zgadywałem żadnych identyfikatorów.

## Krok 0: poświadczenia AWS

Terraform potrzebuje dostępu do konta dopiero od `plan` w górę.

Zalecane: **AWS CLI z SSO**, nie stałe klucze dostępu.

```bash
aws configure sso
aws sso login --profile zoja
export AWS_PROFILE=zoja        # PowerShell: $env:AWS_PROFILE = "zoja"
aws sts get-caller-identity    # sprawdzenie, że działa
```

W GitHub Actions docelowo **OIDC + rola IAM**, nigdy
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` w sekretach repozytorium.

## Krok 1: zebranie identyfikatorów

Uzupełnij tabelę wartościami ze swojego konta. Kolumna „skąd" podaje polecenie
albo miejsce w konsoli.

| Placeholder | Skąd go wziąć |
| --- | --- |
| `<LAMBDA_FUNCTION_NAME>` | `aws lambda list-functions --query "Functions[].FunctionName"` |
| `<LAMBDA_ROLE_NAME>` | `aws lambda get-function-configuration --function-name <NAZWA> --query Role` (nazwa po ostatnim `/`) |
| `<LAMBDA_SECURITY_GROUP_ID>` | `aws ec2 describe-security-groups --filters Name=group-name,Values=zoja-lambda-sg --query "SecurityGroups[].GroupId"` |
| `<RDS_SECURITY_GROUP_ID>` | jw. dla `zoja-rds-sg` |
| `<INGRESS_RULE_ID>` | `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<RDS_SG_ID> --query "SecurityGroupRules[?!IsEgress].SecurityGroupRuleId"` |
| `<LAMBDA_EGRESS_RULE_ID>` | jw. dla SG Lambdy, filtr `[?IsEgress]` |
| `<RDS_EGRESS_RULE_ID>` | jw. dla SG bazy, filtr `[?IsEgress]` |
| `<HTTP_API_ID>` | `aws apigatewayv2 get-apis --query "Items[].{Id:ApiId,Name:Name}"` |
| `<INTEGRATION_ID>` | `aws apigatewayv2 get-integrations --api-id <HTTP_API_ID> --query "Items[].IntegrationId"` |
| `<ROUTE_ID>` | `aws apigatewayv2 get-routes --api-id <HTTP_API_ID> --query "Items[].{Id:RouteId,Key:RouteKey}"` |
| `<STATEMENT_ID>` | `aws lambda get-policy --function-name <NAZWA>` — pole `Sid` w polityce |
| `<FRONTEND_BUCKET_NAME>` | `aws s3 ls` |
| `<DISTRIBUTION_ID>` | `aws cloudfront list-distributions --query "DistributionList.Items[].{Id:Id,Domain:DomainName}"` |
| `<OAC_ID>` | `aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[].{Id:Id,Name:Name}"` |
| `<RESPONSE_HEADERS_POLICY_ID>` | `aws cloudfront list-response-headers-policies --type custom` |
| `<CLOUDFRONT_FUNCTION_NAME>` | `aws cloudfront list-functions --query "FunctionList.Items[].Name"` |

Poza identyfikatorami uzupełnij w `variables.tf` także wartości opisowe:
klasę instancji RDS, wersję silnika, master username, pamięć i timeout Lambdy.
Każde takie miejsce ma komentarz `TODO`.

## Krok 2: import, etapami

Używamy **bloków `import`** z `terraform/imports.tf`, nie komend CLI. Zalety:
trafiają do repozytorium, przechodzą code review, a `plan` pokazuje skutki,
zanim cokolwiek dotknie stanu.

Dla każdego etapu:

```bash
# 1. odkomentuj JEDEN etap w imports.tf i wstaw prawdziwe identyfikatory
terraform plan          # sprawdź, co się stanie
terraform apply         # wykonuje sam import, niczego nie tworzy
```

Kolejność wynika z zależności — najpierw byty samodzielne, potem te, które się
do nich odwołują.

| Etap | Zasoby | Dlaczego tutaj |
| --- | --- | --- |
| 1 | rola IAM, dwa attachmenty polityk, log group | Nic od nich nie zależy. |
| 2 | dwie grupy bezpieczeństwa i ich reguły | Potrzebne przez Lambdę i RDS. |
| 3 | instancja RDS | Zależy od grupy bezpieczeństwa. |
| 4 | Lambda API | Zależy od roli, grupy i podsieci. |
| 5 | HTTP API, integracja, trasa, stage, uprawnienie | Kolejność wewnątrz też ma znaczenie: API przed integracją, integracja przed trasą. |
| 6 | bucket S3 i **cztery** zasoby poboczne | Patrz uwaga niżej. |
| 7 | OAC, Response Headers Policy, CloudFront Function, dystrybucja | Dystrybucja na końcu — dotyka i S3, i API Gateway. |

Sieć **nie jest importowana**. Default VPC i podsieci wchodzą przez `data`,
żeby Terraform mógł je czytać, ale nigdy nie modyfikować.

### Wariant zapasowy: komendy CLI

Gdyby bloki `import` sprawiały kłopot, ta sama operacja przez CLI:

```bash
terraform import aws_iam_role.lambda_exec "<LAMBDA_ROLE_NAME>"
terraform import aws_security_group.rds "<RDS_SECURITY_GROUP_ID>"
terraform import aws_db_instance.postgres "zoja-postgres"
terraform import aws_lambda_function.api "<LAMBDA_FUNCTION_NAME>"
terraform import aws_apigatewayv2_api.http "<HTTP_API_ID>"
terraform import aws_apigatewayv2_integration.lambda "<HTTP_API_ID>/<INTEGRATION_ID>"
terraform import aws_apigatewayv2_route.hello "<HTTP_API_ID>/<ROUTE_ID>"
terraform import 'aws_apigatewayv2_stage.default' "<HTTP_API_ID>/\$default"
terraform import aws_s3_bucket.frontend "<FRONTEND_BUCKET_NAME>"
terraform import aws_cloudfront_distribution.main "<DISTRIBUTION_ID>"
```

W PowerShellu `$default` nie wymaga ucieczki, w bashu tak — stąd `\$default`.

## Krok 3: dojście do zerowego planu

Po każdym imporcie:

```bash
terraform plan
```

Celem jest:

```
No changes. Your infrastructure matches the configuration.
```

**Nie wyjdzie za pierwszym razem i to jest normalne.** Import wypełnia stan
tym, co zwraca AWS, a konfiguracja zawiera moje założenia. Różnice usuwa się
poprawiając **konfigurację**, nigdy zasób w AWS.

> Zasada na cały ten etap: jeśli plan chce coś zmienić, domyślnie błąd jest
> w plikach `.tf`, nie w rzeczywistości.

### Trzy miejsca, w których dryf wystąpi na pewno

**RDS.** Kilka atrybutów `aws_db_instance` istnieje wyłącznie po stronie
Terraforma i nigdy nie wraca z API: `skip_final_snapshot`, `apply_immediately`,
`final_snapshot_identifier`. Ustawiliśmy je zgodnie z intencją, bo nie ma ich
z czym porównać. `password` również nie wraca — dlatego jest pominięte
w konfiguracji i wpisane w `ignore_changes`. Uważaj też na `engine_version`:
przy włączonym auto minor upgrade AWS podbija ją sam, co przy zbyt szczegółowej
wartości daje wieczny dryf.

**S3.** Od wersji 4 providera konfiguracja bucketa jest rozbita na osobne
zasoby. Sam `aws_s3_bucket` to za mało — polityka, blokada dostępu publicznego,
szyfrowanie i własność obiektów to **cztery dodatkowe importy**, każdy po nazwie
bucketa. Pominięcie któregoś kończy się planem, który chce usunąć istniejącą
konfigurację. Przy blokadzie dostępu publicznego oznaczałoby to odsłonięcie bucketa.

**CloudFront.** Najbardziej pracochłonny import w zestawie. Dystrybucja ma
kilkadziesiąt pól, a różnice w kolejności behaviorów albo w wartościach
domyślnych generują pozorny dryf. Najszybsza droga:

```bash
terraform plan -generate-config-out=generated-cloudfront.tf
```

Terraform wypisze konfigurację odpowiadającą rzeczywistości. Przejrzyj ją,
przenieś do `cloudfront.tf` i dopiero wtedy uporządkuj. Plik `generated*.tf`
jest w `.gitignore`, bo to materiał roboczy.

Kod CloudFront Function musi zgadzać się **co do bajta**. Trzymamy go
w `terraform/functions/static-routing.js` i wczytujemy przez `file()`. Jeśli plan
pokaże różnicę, podmień plik na treść z konsoli albo z `terraform show` — nie
zmieniaj funkcji w AWS.

## Czego ten projekt świadomie nie robi

| Zasób | Dlaczego |
| --- | --- |
| Pliki frontendu w S3 | Wgrywa je CI frontendu przez `aws s3 sync`. Terraform zarządza bucketem, nie jego zawartością. |
| Kod Lambdy | Wgrywa go CI backendu przez `update-function-code`. Atrybuty artefaktu są w `ignore_changes`, żeby deploy nie generował dryfu. |
| `DB_PASSWORD` | Ustawiane ręcznie w konsoli Lambdy. Wpisanie do Terraforma umieściłoby hasło w pliku stanu. Cały blok `environment` jest w `ignore_changes`. |
| Default VPC i podsieci | Tylko `data`. Zasób `aws_default_vpc` adoptuje domyślną VPC do stanu i potrafi ją modyfikować. |
| `zoja-db-migrations-lambda` | Jeszcze nie istnieje. Konfiguracja czeka zakomentowana w `lambda-migrations.tf`. |
| NAT Gateway, RDS Proxy, DynamoDB, EC2 | Poza zakresem tego etapu. |

## Zabezpieczenia w konfiguracji

Cztery zasoby mają `prevent_destroy = true`: instancja RDS, bucket frontendu,
dystrybucja CloudFront i log group Lambdy. `terraform destroy` odmówi ich
usunięcia, dopóki ktoś świadomie nie zdejmie tej flagi.

Plik stanu jest lokalny i w `.gitignore`. Zawiera atrybuty zasobów w postaci
jawnej — nie commituj go i nie wysyłaj nikomu.
