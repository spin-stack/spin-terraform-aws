# Where an installation's OpenTofu state lives: once per account and region, before the first
# installation. A bucket for the state, and a KMS key the state is encrypted with - an
# installation's state holds its CA's private key, so it is never a file on somebody's laptop.
#
#   cd bootstrap && tofu init && tofu apply
#
# Then `tofu output -raw init` is the command that sets an installation up to use them.
#
# This configuration's own state is a local file, and holds nothing secret: a key's id and a
# bucket's name. Both resources refuse to be destroyed: without the key, no installation's state
# opens.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  description = "The region the installations are in."
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  # Named for the account and region, which is what makes a bucket's name unique; the key by an
  # alias every installation's configuration names the same way.
  bucket = "spin-tofu-state-${data.aws_caller_identity.current.account_id}-${var.region}"
  alias  = "alias/spin-tofu-state"
}

resource "aws_kms_key" "state" {
  description             = "Encrypts the OpenTofu state of spin installations"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "state" {
  name          = local.alias
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Every version of every state, for as long as it was current and ninety days after: an apply
# that went wrong is a state to go back to.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "old-states"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "bucket" {
  description = "The bucket every installation's state is in."
  value       = aws_s3_bucket.state.bucket
}

output "kms_alias" {
  description = "The key every installation's state is encrypted with."
  value       = aws_kms_alias.state.name
}

output "init" {
  description = "Run this in an installation's directory (examples/complete, or your own copy of it) instead of a bare tofu init."
  value       = "tofu init -backend-config=bucket=${aws_s3_bucket.state.bucket} -backend-config=region=${var.region}"
}
