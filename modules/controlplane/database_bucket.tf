# The database's archive. PostgreSQL runs on the control plane's machine, and every release
# replaces that machine and its disk with it; what makes the database outlive one is a base backup
# and every WAL segment as it is written, shipped here, from which the machine that replaces it
# restores before it serves. Where this is is in the control plane's document (config.tf): the
# database cannot say where its own backup is.
#
# A bucket of its own, which the control plane's role alone reaches (iam.tf, boundary.tf): never
# the volumes', whose credentials hosts hold. What spin writes here is sealed under the
# installation's key before it leaves the machine, so SSE-S3 is the second wrapping, as it is on
# the volumes.
#
# Versioned and under Object Lock, as spin opens every store it writes (its NewS3Store refuses a
# bucket without both): a delete or an overwrite - by a machine that was taken, or a prune gone
# wrong - is a version the lock holds for two weeks rather than a database lost. No force_destroy:
# a destroy that took the archive with it would take the database.

locals {
  database_lock_days = 14
}

resource "aws_s3_bucket" "database" {
  bucket              = "${var.name}-database-${local.account}-${local.region}"
  object_lock_enabled = true
  tags                = local.tags
}

resource "aws_s3_bucket_versioning" "database" {
  bucket = aws_s3_bucket.database.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "database" {
  bucket = aws_s3_bucket.database.id
  rule {
    default_retention {
      # GOVERNANCE, as the volumes': COMPLIANCE is a bill nobody can stop, the account's root
      # included.
      mode = "GOVERNANCE"
      days = local.database_lock_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.database]
}

resource "aws_s3_bucket_public_access_block" "database" {
  bucket                  = aws_s3_bucket.database.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "database" {
  bucket = aws_s3_bucket.database.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "database" {
  bucket = aws_s3_bucket.database.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# What a delete or an overwrite left behind goes a day after the lock that holds it lapses, as on
# the volumes' bucket: asking before would read as an erasure and perform none. The archive the
# database restores from is the current versions; a noncurrent one is only there to undo a mistake.
resource "aws_s3_bucket_lifecycle_configuration" "database" {
  bucket = aws_s3_bucket.database.id
  rule {
    id     = "abandoned-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
  rule {
    id     = "replaced-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = local.database_lock_days + 1
    }
    expiration {
      expired_object_delete_marker = true
    }
  }
  depends_on = [aws_s3_bucket_versioning.database]
}

data "aws_iam_policy_document" "database_bucket" {
  # As the volumes' bucket: objects only through the VPC's endpoint, and TLS always.
  statement {
    sid     = "ObjectsOnlyFromTheVPC"
    effect  = "Deny"
    actions = ["s3:GetObject*", "s3:PutObject*", "s3:DeleteObject*", "s3:RestoreObject", "s3:AbortMultipartUpload"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.database.arn}/*"]
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
    resources = [aws_s3_bucket.database.arn, "${aws_s3_bucket.database.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "database" {
  bucket     = aws_s3_bucket.database.id
  policy     = data.aws_iam_policy_document.database_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.database]
}
