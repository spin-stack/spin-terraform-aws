# The installation's logs, traces and metrics: the stores the leading control plane's machine runs
# keep them here - Quickwit its indexes and its metastore (spin's internal/logstore), and the metric
# store its backups under metrics/, a prefix per backup of which spin keeps the last three
# (internal/metricstore) - and S3's access log of the volumes' bucket under s3-access/volumes/
# (bucket.tf). A bucket of its own and not a prefix of the volumes': what is in it has another
# owner, another retention and another reader, and nothing in it needs the volumes' Object Lock,
# which S3 refuses to deliver an access log into anyway.
#
# No versioning: Quickwit rewrites its metastore in place, and the metric store's backups are
# removed as newer ones complete; every old copy kept would be paid for and never read. No
# expiration rule for the stores: retention is theirs, and a rule deleting under Quickwit would
# leave its metastore naming splits that are gone. The access log is nobody's store, so its prefix
# expires; and the lifecycle clears uploads a machine abandoned halfway.

locals {
  volumes_access_log_prefix = "s3-access/volumes/"
  # Long enough to look back past a revoked host's last credential on a report that came late;
  # every request a host makes is a line, so it is not kept for ever.
  volumes_access_log_days = 90
}

# Unversioned on purpose (above); its own access log would be a log of S3 writing this one.
#trivy:ignore:AWS-0090
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "logs" {
  bucket = "${local.name}-logs-${local.account}-${local.region}"
  # The installation's logs and metrics are kept past a destroy unless it is being removed.
  force_destroy = var.decommission
  tags          = merge(local.tags, { "spin:role" = "logs" })
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

#trivy:ignore:AWS-0132
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
  rule {
    id     = "volumes-access-log"
    status = "Enabled"
    filter {
      prefix = local.volumes_access_log_prefix
    }
    expiration {
      days = local.volumes_access_log_days
    }
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  # As the volumes' bucket: objects only through the VPC's endpoint, and TLS always. S3's log
  # delivery is the one writer from outside the VPC, and only into the access log's prefix.
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
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalServiceName"
      values   = ["logging.s3.amazonaws.com"]
    }
  }
  statement {
    sid       = "VolumesAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/${local.volumes_access_log_prefix}*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    # Only the volumes' bucket's log, in this account: another bucket naming this one as its
    # target is refused.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.volumes.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
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
