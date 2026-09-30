# What this module promises about the issuer, held against its plan with no account: the documents
# it publishes are the committed ones, readable through the distribution alone, over HTTPS alone,
# at id.<domain>.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "aws" {
  alias                       = "us_east_1"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_resource {
  target = aws_cloudfront_distribution.issuer
  values = { arn = "arn:aws:cloudfront::123456789012:distribution/E0SPIN" }
}

variables {
  name      = "spin"
  domain    = "spinbox.dev"
  zone_id   = "Z0SPINPUBLIC"
  documents = "tests/documents"
}

run "the_issuer_publishes_the_committed_documents_and_nothing_else" {
  command = plan

  assert {
    condition     = output.issuer == "https://id.spinbox.dev"
    error_message = "the issuer is not id.<domain>"
  }
  assert {
    condition = (
      toset(keys(aws_s3_object.document)) == toset([".well-known/openid-configuration", ".well-known/jwks.json", ".well-known/allowed_signers"]) &&
      aws_s3_object.document[".well-known/jwks.json"].source == "tests/documents/.well-known/jwks.json" &&
      aws_s3_object.document[".well-known/jwks.json"].etag == filemd5("tests/documents/.well-known/jwks.json") &&
      aws_s3_object.document[".well-known/openid-configuration"].content_type == "application/json" &&
      aws_s3_object.document[".well-known/jwks.json"].content_type == "application/json" &&
      aws_s3_object.document[".well-known/allowed_signers"].content_type == "text/plain"
    )
    error_message = "what is published is not the committed documents, each as what it is"
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.issuer.block_public_acls && aws_s3_bucket_public_access_block.issuer.block_public_policy &&
      aws_s3_bucket_public_access_block.issuer.ignore_public_acls && aws_s3_bucket_public_access_block.issuer.restrict_public_buckets
    )
    error_message = "the bucket can be made public other than through the distribution"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.issuer.statement :
      toset(s.actions) == toset(["s3:GetObject"]) &&
      anytrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudfront.amazonaws.com"])]) &&
    anytrue([for c in s.condition : c.variable == "AWS:SourceArn" && toset(c.values) == toset(["arn:aws:cloudfront::123456789012:distribution/E0SPIN"])])])
    error_message = "something other than this distribution reads the documents, or may do more than read them"
  }
  assert {
    condition = (
      aws_cloudfront_distribution.issuer.aliases == toset(["id.spinbox.dev"]) &&
      alltrue([for b in aws_cloudfront_distribution.issuer.default_cache_behavior :
      b.viewer_protocol_policy == "https-only" && toset(b.allowed_methods) == toset(["GET", "HEAD"])])
    )
    error_message = "the issuer answers other than GET and HEAD over HTTPS at id.<domain>"
  }
  assert {
    condition     = aws_acm_certificate.issuer.domain_name == "id.spinbox.dev" && aws_acm_certificate.issuer.validation_method == "DNS"
    error_message = "the certificate is not id.<domain>'s"
  }
  assert {
    condition     = toset(keys(aws_route53_record.issuer)) == toset(["A", "AAAA"]) && alltrue([for r in aws_route53_record.issuer : r.name == "id.spinbox.dev" && r.zone_id == "Z0SPINPUBLIC"])
    error_message = "id.<domain> does not point at the distribution in the domain's zone"
  }
}
