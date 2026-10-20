# What each machine starts on (config.tf): one object per role, written by an apply and read by
# that role's machines, each under its own role and only its own (iam.tf, proxy.tf, the runners
# module). Not the parameter store: the control plane's document carries what each image's release
# signed of it (attested_key.tf), past the 8 KB the largest parameter holds (fresh-install runs
# 39161868759 and 39163437919). A bucket of its own: what is here has its writer in the apply
# alone, and no machine writes it (boundary.tf).
#
# Versioned, so a document an apply replaced can be read back; nothing is under Object Lock, as
# what is here is the apply's to write again.

# No access log: its one writer is the apply, its readers each a role's own machines.
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "documents" {
  bucket = local.documents_bucket
  # What is here is the apply's to write again: nothing is lost with it.
  force_destroy = true
  tags          = merge(local.tags, { "spin:role" = "documents" })
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    id     = "replaced-documents"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
  depends_on = [aws_s3_bucket_versioning.documents]
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3: a document holds no secret (config.tf), and who reads one is its role's policy.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# TLS always. Not objects only through the VPC's endpoint, as the other buckets: the apply writes
# the documents, and reads them back at every plan, from outside it.
data "aws_iam_policy_document" "documents_bucket" {
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# None while the installation is being removed, as the volumes' (bucket.tf).
resource "aws_s3_bucket_policy" "documents" {
  count      = var.decommission ? 0 : 1
  bucket     = aws_s3_bucket.documents.id
  policy     = data.aws_iam_policy_document.documents_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.documents]
}
