# The installation's logs, traces and metrics: the stores the leading control plane's machine runs
# keep them here - Quickwit its indexes and its metastore (spin's internal/logstore), and the metric
# store its backups under metrics/, a prefix per backup of which spin keeps the last three
# (internal/metricstore). A bucket of its own and not a prefix of the volumes': what is in it has
# another owner, another retention and another reader, and nothing in it needs the volumes' Object
# Lock.
#
# No versioning: Quickwit rewrites its metastore in place, and the metric store's backups are
# removed as newer ones complete; every old copy kept would be paid for and never read. No
# expiration rule either: retention is the stores', and a rule deleting under Quickwit would leave
# its metastore naming splits that are gone. What a lifecycle does do here is clear uploads a
# machine abandoned halfway.

resource "aws_s3_bucket" "logs" {
  bucket = "${local.name}-logs-${local.account}-${local.region}"
  # The installation's logs and metrics are kept past a destroy unless it is being removed.
  force_destroy = var.decommission
  tags          = local.tags
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

# None while the installation is being removed, as the volumes' (bucket.tf).
resource "aws_s3_bucket_policy" "logs" {
  count      = var.decommission ? 0 : 1
  bucket     = aws_s3_bucket.logs.id
  policy     = data.aws_iam_policy_document.logs_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.logs]
}
