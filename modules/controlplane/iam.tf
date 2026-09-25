# Two roles. The control plane's instance role opens the bucket and reads its document. The
# runner-scope role is what it assumes to mint each runner's credential (--s3-role-arn): for an
# hour, narrowed by a session policy to the volumes that runner serves
# (spin's internal/server/volumeserver/storagecreds.go). Its own permissions are the widest that
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
  name                 = "${var.name}-controlplane"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

resource "aws_iam_instance_profile" "controlplane" {
  name = "${var.name}-controlplane"
  role = aws_iam_role.controlplane.name
  tags = local.tags
}

# Session Manager instead of SSH: no port 22, no key pair to lose - and Session Manager alone,
# the agent's registration and its channels. AmazonSSMManagedInstanceCore, which is what it is
# usually given, also grants ssm:GetParameter and GetParameters on every parameter in the
# account, and the parameters here are read under the account's aws/ssm key: attached to the
# proxy and the runners, it gave either the control plane's encryption key.
data "aws_iam_policy_document" "session_manager" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "session_manager" {
  name        = "${var.name}-session-manager"
  description = "Session Manager into a machine of the ${var.name} installation, and nothing else of SSM"
  policy      = data.aws_iam_policy_document.session_manager.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "controlplane_ssm" {
  role       = aws_iam_role.controlplane.name
  policy_arn = aws_iam_policy.session_manager.arn
}

locals {
  # Spelled out rather than read off the roles: the boundary names them, and the roles carry
  # the boundary.
  runner_scope_arn      = "arn:aws:iam::${local.account}:role/${var.name}-runner-scope"
  controlplane_role_arn = "arn:aws:iam::${local.account}:role/${var.name}-controlplane"
  runner_role_arn       = "arn:aws:iam::${local.account}:role/${var.name}-runner"
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
  # Its logs and traces: the store it runs reads and writes its indexes and its metastore here,
  # and deletes the splits retention drops. Nothing else is given this bucket - a runner's
  # credentials are minted for the volumes' alone.
  statement {
    sid       = "TheLogs"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
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
  # What it starts on, and the secrets its document names. Read, never written: every parameter
  # of the installation is this module's to write (secrets.tf).
  statement {
    sid     = "ItsDocumentAndSecrets"
    actions = ["ssm:GetParameter"]
    resources = [for p in [local.config_parameter, local.installation_parameter, local.key_parameter, local.ca_parameter, local.admin_password_parameter] :
    "arn:aws:ssm:${local.region}:${local.account}:parameter${p}"]
  }
  # The database, as spin and as nobody else: an IAM token for that one database user.
  statement {
    sid       = "SignInToTheDatabase"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${local.region}:${local.account}:dbuser:${aws_db_instance.database.resource_id}/spin"]
  }
  # Its own name in the internal zone, and nothing else there: what a new machine takes when it
  # takes the installation over.
  statement {
    sid       = "ItsName"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.internal.arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = [local.cp_host]
    }
  }
  # Its group of one: in service once it leads, and to be replaced when it stays down.
  statement {
    sid = "ItsGroup"
    actions = ["autoscaling:CompleteLifecycleAction", "autoscaling:RecordLifecycleActionHeartbeat",
    "autoscaling:SetInstanceHealth"]
    resources = ["arn:aws:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.controlplane_group}"]
  }
  # The master's password, which the first boot uses to make that user. RDS keeps it and the
  # machine reads it; nothing else of Secrets Manager.
  statement {
    sid       = "MakeTheDatabasesUser"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.database.master_user_secret[0].secret_arn]
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
  name                 = "${var.name}-runner-scope"
  assume_role_policy   = data.aws_iam_policy_document.runner_scope_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  # A runner's credential lasts an hour (StorageCredentialTTL), which is also the most a role
  # assumed from another role's session can be given.
  max_session_duration = 3600
  tags                 = local.tags
}

data "aws_iam_policy_document" "runner_scope" {
  statement {
    # ListBucket is what makes S3 answer a key that is not there with 404 rather than 403, and a
    # volume with nothing published yet has no HEAD: without it every host read that absence as a
    # credential it could not use and refused to serve the volume.
    actions = ["s3:GetBucketVersioning", "s3:GetBucketObjectLockConfiguration", "s3:ListBucketVersions",
    "s3:ListBucket"]
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
