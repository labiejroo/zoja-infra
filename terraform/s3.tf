# ---------------------------------------------------------------------------
# S3 — BUCKET FRONTENDU, ISTNIEJE, DO IMPORTU
#
# UWAGA NA ROZBICIE ZASOBÓW
# Od wersji 4 providera AWS konfiguracja bucketa nie mieści się już w jednym
# zasobie. Polityka, blokada dostępu publicznego, szyfrowanie i własność
# obiektów to OSOBNE zasoby, każdy z własnym importem (identyfikatorem jest
# nazwa bucketa). Pominięcie któregokolwiek kończy się planem, który chce
# usunąć istniejącą konfigurację — co przy blokadzie dostępu publicznego
# oznaczałoby odsłonięcie bucketa.
#
# ZAWARTOŚCI BUCKETA TERRAFORM NIE DOTYKA.
# Pliki z out/ wgrywa CI frontendu przez aws s3 sync. Nie ma tu żadnego
# aws_s3_object i nie powinno być.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket = var.frontend_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Bucket jest prywatny. Dostęp wyłącznie przez CloudFront z OAC.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Polityka wpuszczająca WYŁĄCZNIE tę jedną dystrybucję CloudFront.
# Warunek AWS:SourceArn jest tu istotny: bez niego każda dystrybucja
# w dowolnym koncie AWS mogłaby czytać bucket przez OAC.
data "aws_iam_policy_document" "frontend_bucket" {
  policy_id = "PolicyForCloudFrontPrivateContent"
  version   = "2008-10-17"

  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*",
    ]

    principals {
      type = "Service"
      identifiers = [
        "cloudfront.amazonaws.com",
      ]
    }

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.main.arn,
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}
