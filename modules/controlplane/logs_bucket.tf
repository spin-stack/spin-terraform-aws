# The installation's logs and traces: the store the leading control plane runs (spin's
# internal/logstore) keeps its indexes and its metastore here. A bucket of its own and not a
# prefix of the volumes': what is in it has another owner, another retention and another reader,
# and nothing in it needs the volumes' Object Lock.
#
# No versioning: Quickwit rewrites its metastore in place, and every old copy kept would be paid
# for and never read. No expiration rule either: retention is the store's, split by split, and a
# rule deleting under it would leave the metastore naming splits that are gone. What a lifecycle
# does do here is clear uploads a machine abandoned halfway.

resource "aws_s3_bucket" "logs" {
  bucket = "${var.name}-logs-${local.account}-${local.region}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    # SSE-S3, as the volumes'. Who can read the logs is decided by who can reach this bucket,
    # which is the control plane's role alone; a KMS key would charge per request for no second
    # reader it keeps out.
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "abandoned-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  # As the volumes' bucket: objects only through the VPC's endpoint, and TLS always.
  statement {
    sid     = "ObjectsOnlyFromTheVPC"
    effect  = "Deny"
    actions = ["s3:GetObject*", "s3:PutObject*", "s3:DeleteObject*", "s3:RestoreObject", "s3:AbortMultipartUpload"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/*"]
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
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket     = aws_s3_bucket.logs.id
  policy     = data.aws_iam_policy_document.logs_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.logs]
}
