# The installation's identity issuer: https://id.<domain>, where a system outside spin reads the
# discovery document and the key set that verify a workspace's identity token.
#
# Its own origin, and nothing of the installation's serves it: whoever writes the key set decides
# which tokens are the installation's. What is published is what `spin-controlplane identity
# documents` wrote from the KMS key's public half (modules/controlplane's identity_documents) and
# was committed where this is applied from - so a changed key is a change somebody reviews, and no
# machine of the installation can write here.

variable "name" {
  description = "The installation's name, as modules/controlplane's name output says it."
  type        = string
}

variable "domain" {
  description = "The installation's domain: the issuer is id.<domain>."
  type        = string
}

variable "zone_id" {
  description = "The domain's public zone (modules/controlplane's public_zone_id)."
  type        = string
}

variable "documents" {
  description = "The directory `spin-controlplane identity documents --out` wrote: it holds .well-known/openid-configuration and .well-known/jwks.json."
  type        = string
}

variable "tags" {
  description = "Tags every resource carries."
  type        = map(string)
  default     = {}
}

locals {
  host = "id.${var.domain}"
  documents = {
    ".well-known/openid-configuration" = "${var.documents}/.well-known/openid-configuration"
    ".well-known/jwks.json"            = "${var.documents}/.well-known/jwks.json"
  }
}

data "aws_caller_identity" "current" {}

# The two documents and nothing else; public only through the distribution (the policy below).
# Unversioned and unlogged: what is in it is in git, and a read of a public key set says nothing.
#trivy:ignore:AWS-0090
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "issuer" {
  bucket        = "${var.name}-identity-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "issuer" {
  bucket                  = aws_s3_bucket.issuer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "issuer" {
  bucket = aws_s3_bucket.issuer.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public documents: a key of the account's would only make CloudFront's reads of them need it.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "issuer" {
  bucket = aws_s3_bucket.issuer.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "document" {
  for_each     = local.documents
  bucket       = aws_s3_bucket.issuer.id
  key          = each.key
  source       = each.value
  etag         = filemd5(each.value)
  content_type = "application/json"
  # A relying party reads the key set when it sees a key id it does not know, and again after
  # this long: a rotation publishes the next key beside this one well before it signs.
  cache_control = "public, max-age=300"
  tags          = var.tags
}

data "aws_iam_policy_document" "issuer" {
  statement {
    sid       = "TheDistributionReadsTheDocuments"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.issuer.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.issuer.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "issuer" {
  bucket = aws_s3_bucket.issuer.id
  policy = data.aws_iam_policy_document.issuer.json
}

resource "aws_acm_certificate" "issuer" {
  provider          = aws.us_east_1
  domain_name       = local.host
  validation_method = "DNS"
  tags              = var.tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = { for o in aws_acm_certificate.issuer.domain_validation_options : o.domain_name => o }
  zone_id  = var.zone_id
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  records  = [each.value.resource_record_value]
  ttl      = 300
}

resource "aws_acm_certificate_validation" "issuer" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.issuer.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_cloudfront_origin_access_control" "issuer" {
  name                              = "${var.name}-identity"
  description                       = "${var.name}: the identity issuer's documents"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# No WAF and no access log: two static public documents, which a relying party reads now and then.
#trivy:ignore:AWS-0010
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "issuer" {
  enabled         = true
  comment         = "${var.name}: the identity issuer, ${local.host}"
  aliases         = [local.host]
  price_class     = "PriceClass_100"
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    origin_id                = "documents"
    domain_name              = aws_s3_bucket.issuer.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.issuer.id
  }

  default_cache_behavior {
    target_origin_id       = "documents"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    # AWS's managed CachingOptimized: the objects' own max-age decides.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    compress        = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.issuer.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}

resource "aws_route53_record" "issuer" {
  for_each = toset(["A", "AAAA"])
  zone_id  = var.zone_id
  name     = local.host
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.issuer.domain_name
    zone_id                = aws_cloudfront_distribution.issuer.hosted_zone_id
    evaluate_target_health = false
  }
}

output "issuer" {
  description = "The issuer a workspace's identity token names, which a relying party is configured with."
  value       = "https://${local.host}"
}
