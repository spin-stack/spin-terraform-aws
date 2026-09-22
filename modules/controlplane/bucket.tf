# Every workspace's disk. Made here with what spin requires of it - versioning and Object Lock
# with a default retention, which `controlplane storage configure` checks and would otherwise
# set - so the lock is declared rather than left to whichever process made the bucket first.
#
# Its lifecycle rules are not declared: spin writes them (its internal/storage/simio/real), merged
# by name into whatever is there, and a lifecycle configuration here would replace them on
# every apply.

resource "aws_s3_bucket" "volumes" {
  bucket              = "${var.name}-volumes-${local.account}-${local.region}"
  object_lock_enabled = true
  tags                = local.tags
}

resource "aws_s3_bucket_versioning" "volumes" {
  bucket = aws_s3_bucket.volumes.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "volumes" {
  bucket = aws_s3_bucket.volumes.id
  rule {
    default_retention {
      # GOVERNANCE: COMPLIANCE is a bill nobody can stop, the account's root included.
      mode = "GOVERNANCE"
      days = var.object_lock_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.volumes]
}

resource "aws_s3_bucket_public_access_block" "volumes" {
  bucket                  = aws_s3_bucket.volumes.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "volumes" {
  bucket = aws_s3_bucket.volumes.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "volumes" {
  bucket = aws_s3_bucket.volumes.id
  rule {
    # SSE-S3 under the envelope spin already seals every layer with: a KMS key here would
    # charge per request for a second wrapping of bytes nobody can read without the first.
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  # Object reads and writes only through the VPC's endpoint. Bucket-level calls are left open
  # to the account, so whoever runs this module can still read and change the bucket's
  # configuration from outside it.
  statement {
    sid     = "ObjectsOnlyFromTheVPC"
    effect  = "Deny"
    actions = ["s3:GetObject*", "s3:PutObject*", "s3:DeleteObject*", "s3:RestoreObject", "s3:AbortMultipartUpload"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.volumes.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.s3.id]
    }
  }
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.volumes.arn, "${aws_s3_bucket.volumes.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "volumes" {
  bucket     = aws_s3_bucket.volumes.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.volumes]
}
