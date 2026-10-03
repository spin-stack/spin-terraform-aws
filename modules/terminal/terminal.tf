# The installation's browser terminal: https://term.<domain>, the SSH client a person reaches a
# workspace with from a browser - the CLI's own Go, compiled to WebAssembly, holding a session to
# the workspace's launch claim with anchors built in at release, and logging in with a passkey.
#
# Its own origin, and nothing of the installation serves or writes it: whoever writes its files
# writes the code that asks a person's passkey. What is published is the spin release's signed
# spin-term.tar.gz, verified and unpacked by `task term:fetch` into the directory `files` names,
# pinned by `release`; the bucket's policy refuses a write by any role of the installation.

variable "name" {
  description = "The installation's name, as modules/controlplane's name output says it."
  type        = string
}

variable "iam_name" {
  description = "The prefix of the installation's roles (modules/controlplane's iam_name): every one is refused a write here."
  type        = string
}

variable "domain" {
  description = "The installation's domain: the terminal is term.<domain>, and asks app.<domain>."
  type        = string
}

variable "zone_id" {
  description = "The domain's public zone (modules/controlplane's public_zone_id)."
  type        = string
}

variable "release" {
  description = "The spin release whose terminal is published, which `files` must be: the terminal holds a launch claim to the release window around it."
  type        = string
}

variable "files" {
  description = "The directory `task term:fetch RELEASE=<release>` unpacked the release's verified spin-term.tar.gz into: index.html, term.wasm, wasm_exec.js, assets/, and the RELEASE it is."
  type        = string
}

variable "tags" {
  description = "Tags every resource carries."
  type        = map(string)
  default     = {}
}

locals {
  host = "term.${var.domain}"
  # What the release's tarball holds, as fetched: RELEASE is term:fetch's, and not published.
  files = toset([for f in fileset(var.files, "**") : f if f != "RELEASE"])
  types = {
    html = "text/html; charset=utf-8"
    js   = "text/javascript"
    css  = "text/css"
    wasm = "application/wasm"
    json = "application/json"
    svg  = "image/svg+xml"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The terminal's files and nothing else; public only through the distribution (the policy below).
# Unversioned and unlogged: what is in it is a signed release's, and a read of it says nothing.
#trivy:ignore:AWS-0090
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "terminal" {
  bucket        = "${var.name}-term-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = merge(var.tags, { "spin:role" = "terminal" })
}

resource "aws_s3_bucket_public_access_block" "terminal" {
  bucket                  = aws_s3_bucket.terminal.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terminal" {
  bucket = aws_s3_bucket.terminal.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public files: a key of the account's would only make CloudFront's reads of them need it.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "terminal" {
  bucket = aws_s3_bucket.terminal.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "file" {
  for_each     = local.files
  bucket       = aws_s3_bucket.terminal.id
  key          = each.value
  source       = "${var.files}/${each.value}"
  etag         = filemd5("${var.files}/${each.value}")
  content_type = lookup(local.types, reverse(split(".", each.value))[0], "application/octet-stream")
  # The bundler names what it builds by its content, so those never change under their name; the
  # page and the terminal's Go keep theirs across releases, and are asked again each time.
  cache_control = startswith(each.value, "assets/") ? "public, max-age=31536000, immutable" : "no-cache"
  tags          = var.tags

  lifecycle {
    precondition {
      condition     = trimspace(file("${var.files}/RELEASE")) == var.release
      error_message = "the terminal's files are not release ${var.release}'s: run task term:fetch RELEASE=${var.release}"
    }
  }
}

data "aws_iam_policy_document" "terminal" {
  statement {
    sid       = "TheDistributionReadsTheFiles"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.terminal.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.terminal.arn]
    }
  }
  # Whoever writes these files writes the code that asks a person's passkey: no role of the
  # installation does, whatever it is given later - a machine that was taken included.
  statement {
    sid    = "NoRoleOfTheInstallationWritesTheTerminal"
    effect = "Deny"
    actions = [
      "s3:PutObject*", "s3:DeleteObject*", "s3:RestoreObject", "s3:PutBucket*", "s3:DeleteBucket*",
      "s3:PutLifecycleConfiguration", "s3:PutReplicationConfiguration",
    ]
    resources = [aws_s3_bucket.terminal.arn, "${aws_s3_bucket.terminal.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.iam_name}-*"]
    }
  }
}

resource "aws_s3_bucket_policy" "terminal" {
  bucket = aws_s3_bucket.terminal.id
  policy = data.aws_iam_policy_document.terminal.json
}

resource "aws_acm_certificate" "terminal" {
  provider          = aws.us_east_1
  domain_name       = local.host
  validation_method = "DNS"
  tags              = var.tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = { for o in aws_acm_certificate.terminal.domain_validation_options : o.domain_name => o }
  zone_id  = var.zone_id
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  records  = [each.value.resource_record_value]
  ttl      = 300
}

resource "aws_acm_certificate_validation" "terminal" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.terminal.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_cloudfront_origin_access_control" "terminal" {
  name                              = "${var.name}-term"
  description                       = "${var.name}: the browser terminal's files"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# What the page may do, said by the origin and not by the page: run its own scripts and its own
# WebAssembly, ask the dashboard's API and the relay and nothing else, and be framed by nobody.
resource "aws_cloudfront_response_headers_policy" "terminal" {
  name    = "${var.name}-term"
  comment = "${var.name}: the browser terminal's own policy"
  security_headers_config {
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'none'",
        "script-src 'self' 'wasm-unsafe-eval'",
        "style-src 'self' 'unsafe-inline'",
        "connect-src 'self' https://app.${var.domain} wss://tunnel.app.${var.domain}",
        "img-src 'self' data:",
        "font-src 'self'",
        "base-uri 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
      ])
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
  }
}

# No WAF and no access log: a release's static files, the same for every reader.
#trivy:ignore:AWS-0010
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "terminal" {
  enabled             = true
  comment             = "${var.name}: the browser terminal, ${local.host}, release ${var.release}"
  aliases             = [local.host]
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id                = "files"
    domain_name              = aws_s3_bucket.terminal.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.terminal.id
  }

  default_cache_behavior {
    target_origin_id           = "files"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    response_headers_policy_id = aws_cloudfront_response_headers_policy.terminal.id
    # AWS's managed CachingOptimized: the objects' own Cache-Control decides.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    compress        = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.terminal.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}

resource "aws_route53_record" "terminal" {
  for_each = toset(["A", "AAAA"])
  zone_id  = var.zone_id
  name     = local.host
  type     = each.value
  alias {
    name                   = aws_cloudfront_distribution.terminal.domain_name
    zone_id                = aws_cloudfront_distribution.terminal.hosted_zone_id
    evaluate_target_health = false
  }
}

output "url" {
  description = "The browser terminal's origin, which the dashboard opens a workspace's terminal at."
  value       = "https://${local.host}"
}
