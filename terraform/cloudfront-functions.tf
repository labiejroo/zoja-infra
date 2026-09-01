# ---------------------------------------------------------------------------
# CLOUDFRONT FUNCTION — ISTNIEJE, DO IMPORTU
#
# ZAKRES: WYŁĄCZNIE ROUTING TRAS STATYCZNYCH.
# Next.js z output "export" generuje płaskie pliki: admin.html, decision.html,
# cancel.html. CloudFront z originem S3 nie rozwiązuje adresów bez rozszerzenia,
# więc bez tej funkcji /admin zwróciłoby 404.
#
# Funkcja NIE dotyka tokenów. Linki decyzyjne mają postać /decision?t=<token>,
# czyli token jest query stringiem — CloudFront przekazuje go nietkniętym
# i nie musi nawet wiedzieć, że istnieje.
#
# KOD W OSOBNYM PLIKU
# Przy imporcie CloudFront zwraca kod funkcji i Terraform porównuje go co do
# bajta. Trzymanie go w pliku .js zamiast w heredocu w HCL sprawia, że łatwo
# wkleić dokładnie to, co zwróci terraform show — bez walki z wcięciami.
# ---------------------------------------------------------------------------

resource "aws_cloudfront_function" "static_routing" {
  name    = var.cloudfront_function_name
  runtime = "cloudfront-js-2.0" # TODO: sprawdź runtime w konsoli (może być 1.0).
  comment = "Mapowanie tras statycznych na pliki .html"
  publish = true
  code    = file("${path.module}/functions/static-routing.js")
}
