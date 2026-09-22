# Two roles. The control plane's instance role opens the bucket and publishes to SSM. The
# runner-scope role is what it assumes to mint each runner's credential (--s3-role-arn): for an
# hour, narrowed by a session policy to the volumes that runner serves
# (internal/server/volumeserver/storagecreds.go). Its own permissions are the widest that
# session policy ever asks for, so the narrowing is the control plane's and the ceiling is here.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controlplane" {
  name               = "${var.name}-controlplane"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "controlplane" {
  name = "${var.name}-controlplane"
  role = aws_iam_role.controlplane.name
  tags = local.tags
}

# Session Manager instead of SSH: no port 22, no key pair to lose.
resource "aws_iam_role_policy_attachment" "controlplane_ssm" {
  role       = aws_iam_role.controlplane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

locals {
  ssm_prefix = "arn:aws:ssm:${local.region}:${local.account}:parameter/${var.name}"
}

data "aws_iam_policy_document" "controlplane" {
  statement {
    sid       = "TheBucket"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.volumes.arn, "${aws_s3_bucket.volumes.arn}/*"]
  }
  # Nothing in spin bypasses a retention or rewrites the bucket's policy, and a control plane
  # that could would make the lock and the endpoint condition its own to lift. It writes the
  # lock's rule only to a bucket that has none, and this one is made with one. Versioning is
  # left writable: the bootstrap enables it on every configure, and S3 refuses to suspend it on
  # a bucket under Object Lock.
  statement {
    sid    = "NotTheLock"
    effect = "Deny"
    actions = [
      "s3:BypassGovernanceRetention", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:DeleteBucket",
      "s3:PutBucketObjectLockConfiguration",
    ]
    resources = [aws_s3_bucket.volumes.arn, "${aws_s3_bucket.volumes.arn}/*"]
  }
  # The runners' group, which the runners module names ${name}-runners: the control plane
  # starts a host when a workspace waits for one and empties the group when nothing runs.
  # Describe has no resource-level permission; the resize is held to that one group.
  statement {
    sid       = "SizeTheRunners"
    actions   = ["autoscaling:SetDesiredCapacity"]
    resources = ["arn:aws:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.runner_group}"]
  }
  statement {
    sid       = "SeeTheRunners"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "MintRunnerCredentials"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.runner_scope.arn]
  }
  # The pool's token and the CA, which it publishes for runners, and the encryption key, which
  # it backs up there on its first start and reads back on a volume that lost it.
  statement {
    sid       = "Publish"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = ["${local.ssm_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "controlplane" {
  name   = "spin"
  role   = aws_iam_role.controlplane.id
  policy = data.aws_iam_policy_document.controlplane.json
}

data "aws_iam_policy_document" "runner_scope_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
  }
}

resource "aws_iam_role" "runner_scope" {
  name               = "${var.name}-runner-scope"
  assume_role_policy = data.aws_iam_policy_document.runner_scope_trust.json
  # A runner's credential lasts an hour (StorageCredentialTTL), which is also the most a role
  # assumed from another role's session can be given.
  max_session_duration = 3600
  tags                 = local.tags
}

data "aws_iam_policy_document" "runner_scope" {
  statement {
    actions   = ["s3:GetBucketVersioning", "s3:GetBucketObjectLockConfiguration", "s3:ListBucketVersions"]
    resources = [aws_s3_bucket.volumes.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.volumes.arn}/layers/*", "${aws_s3_bucket.volumes.arn}/volumes/*"]
  }
}

resource "aws_iam_role_policy" "runner_scope" {
  name   = "spin"
  role   = aws_iam_role.runner_scope.id
  policy = data.aws_iam_policy_document.runner_scope.json
}
