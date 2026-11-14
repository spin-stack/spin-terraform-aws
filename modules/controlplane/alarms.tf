# Whoever security_emails names, and has confirmed, is told when the control plane's role starts a
# machine itself; with nobody named, the call is only on record in the trail. Auto Scaling starts the
# runners, under its own service role; spin has no call to RunInstances. The role holds that
# permission only because Auto Scaling asks it of whoever names a launch template, and a machine it
# started itself could boot the runners' image with other user data, which nothing measures.
#
# The role cannot silence this: the boundary denies it EventBridge, SNS and every CloudTrail write,
# and it is granted nothing of this bucket. Telling comes after the fact, by minutes.

locals {
  calls_bucket = "${local.name}-calls-${local.account}-${local.region}"
  calls_trail  = "${local.name}-calls"
  # The trail's own name, as its bucket's policy must say before the trail can exist.
  calls_trail_arn = "arn:${data.aws_partition.current.partition}:cloudtrail:${local.region}:${local.account}:trail/${local.calls_trail}"
}

# No access log: its one writer is CloudTrail, and nothing reads it but a person in an incident.
# Not versioned: nothing writes over a call, and the lifecycle below ends them all.
#trivy:ignore:AWS-0089
#trivy:ignore:AWS-0090
resource "aws_s3_bucket" "calls" {
  bucket = local.calls_bucket
  # What is here says what happened and decides nothing: an installation being removed takes it along.
  force_destroy = true
  tags          = merge(local.tags, { "spin:role" = "calls" })
}

resource "aws_s3_bucket_lifecycle_configuration" "calls" {
  bucket = aws_s3_bucket.calls.id
  rule {
    id     = "old-calls"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "calls" {
  bucket                  = aws_s3_bucket.calls.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "calls" {
  bucket = aws_s3_bucket.calls.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3: API calls hold no secret, and only an administrator of the account reads them.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "calls" {
  bucket = aws_s3_bucket.calls.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "calls_bucket" {
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.calls.arn, "${aws_s3_bucket.calls.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid       = "TheTrailReadsTheBucketsAcl"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.calls.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.calls_trail_arn]
    }
  }
  statement {
    sid       = "TheTrailWrites"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.calls.arn}/AWSLogs/${local.account}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.calls_trail_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "calls" {
  bucket     = aws_s3_bucket.calls.id
  policy     = data.aws_iam_policy_document.calls_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.calls]
}

# EventBridge sees an API call only through a trail. One region, because the launch template the
# role is held to is this region's; writes only, because that is what the rule asks.
#trivy:ignore:AWS-0014
#trivy:ignore:AWS-0015
#trivy:ignore:AWS-0162
resource "aws_cloudtrail" "calls" {
  name                          = local.calls_trail
  s3_bucket_name                = aws_s3_bucket.calls.id
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  tags                          = merge(local.tags, { "spin:role" = "calls" })

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.calls]
}

# AWS's own key cannot be used here: EventBridge may not read it, and nothing secret is sent.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "security" {
  name = "${local.iam_name}-security"
  tags = merge(local.tags, { "spin:role" = "calls" })
}

data "aws_iam_policy_document" "security_topic" {
  statement {
    sid       = "TheRulePublishes"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.controlplane_starts_a_machine.arn]
    }
  }
  # This policy replaces the topic's default, which let the account's own alarms publish.
  statement {
    sid       = "TheMachinesAlarmPublishes"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_metric_alarm.controlplane_machine.arn]
    }
  }
}

resource "aws_sns_topic_policy" "security" {
  arn    = aws_sns_topic.security.arn
  policy = data.aws_iam_policy_document.security_topic.json
}

resource "aws_sns_topic_subscription" "security" {
  for_each  = toset(var.security_emails)
  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = each.value
}

# A call that failed started nothing; a dry run, as Auto Scaling may ask for, reads as a failure.
resource "aws_cloudwatch_event_rule" "controlplane_starts_a_machine" {
  name        = "${local.iam_name}-cp-runs-instances"
  description = "The control plane's role called RunInstances itself, which only Auto Scaling's should."
  tags        = local.tags
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["RunInstances"]
      errorCode = [{ exists = false }]
      userIdentity = {
        sessionContext = {
          sessionIssuer = {
            arn = [aws_iam_role.controlplane.arn]
          }
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "controlplane_starts_a_machine" {
  rule = aws_cloudwatch_event_rule.controlplane_starts_a_machine.name
  arn  = aws_sns_topic.security.arn
}
