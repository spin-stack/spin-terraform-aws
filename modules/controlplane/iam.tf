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
  name                 = "${local.iam_name}-controlplane"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

resource "aws_iam_instance_profile" "controlplane" {
  name = "${local.iam_name}-controlplane"
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
  name        = "${local.iam_name}-session-manager"
  description = "Session Manager into a machine of the ${local.name} installation in ${local.region}, and nothing else of SSM"
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
  runner_scope_arn      = "${local.arn}:iam::${local.account}:role/${local.iam_name}-runner-scope"
  controlplane_role_arn = "${local.arn}:iam::${local.account}:role/${local.iam_name}-controlplane"
  runner_role_arn       = "${local.arn}:iam::${local.account}:role/${local.iam_name}-runner"
  proxy_role_arn        = "${local.arn}:iam::${local.account}:role/${local.iam_name}-proxy"
}

data "aws_iam_policy_document" "controlplane" {
  # What spin does with the bucket, and nothing it does not: list it and read what it is made
  # with (versioning, the lock, the lifecycle, which configure checks), and read, write, mark
  # deleted, hold and release its objects. Deleting a version is how a delete is undone (the
  # marker is a version); the lock refuses it on anything it still holds.
  statement {
    sid = "TheBucket"
    actions = ["s3:ListBucket", "s3:ListBucketVersions", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation",
    "s3:GetBucketVersioning", "s3:GetBucketObjectLockConfiguration", "s3:GetLifecycleConfiguration"]
    resources = [aws_s3_bucket.volumes.arn]
  }
  statement {
    sid = "ItsObjects"
    actions = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion",
      "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObjectLegalHold", "s3:GetObjectLegalHold",
    "s3:GetObjectRetention"]
    resources = ["${aws_s3_bucket.volumes.arn}/*"]
  }
  # Nothing in spin bypasses a retention or configures the bucket, and a control plane that could
  # would make the lock, the endpoint condition and the lifecycle its own to lift: a lifecycle
  # rule alone expires every volume without an object being touched. Denied as well as not
  # granted, so a grant added later for something else does not bring them back.
  statement {
    sid    = "NotTheLockNorTheBucketsConfiguration"
    effect = "Deny"
    actions = [
      "s3:BypassGovernanceRetention", "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:CreateBucket",
      "s3:PutBucket*", "s3:PutLifecycleConfiguration", "s3:PutEncryptionConfiguration",
      "s3:PutReplicationConfiguration", "s3:PutIntelligentTieringConfiguration", "s3:PutInventoryConfiguration",
      "s3:PutAnalyticsConfiguration", "s3:PutMetricsConfiguration", "s3:PutAccelerateConfiguration",
      "s3:PutObjectAcl",
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
  # The database's archive: the base backups and the WAL it ships, the restore that reads them
  # back, and the prune of what a newer base backup made unneeded. No version is read or deleted:
  # what a delete leaves is the bucket's to expire (database_bucket.tf), not this role's to erase.
  # Its versioning and its lock are read, never written: spin opens no store without both.
  statement {
    sid       = "TheDatabasesArchive"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning", "s3:GetBucketObjectLockConfiguration"]
    resources = [aws_s3_bucket.database.arn]
  }
  statement {
    sid       = "TheDatabasesArchiveObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.database.arn}/*"]
  }
  # The runners' group, which the runners module names ${name}-runners: the control plane
  # starts a host when a workspace waits for one, empties the group when nothing runs, and gives
  # back one host that holds nothing only it has, by its instance, with the group one smaller.
  # Describe has no resource-level permission; the resize and the removal are held to that group.
  statement {
    sid       = "SizeTheRunners"
    actions   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
    resources = ["${local.arn}:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.runner_group}"]
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
  # A grant of a volume's key: a session tagged with its owner (volume_keys.tf). What the
  # control plane may do with the key itself is the key's policy.
  statement {
    sid       = "GrantVolumeKeys"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.volume_keys.arn]
  }
  # A grant of the identity key: a session of the identity-keys role (identity.tf). What the
  # control plane may do with the key itself - make it unseen, and nothing else - is the key's policy.
  statement {
    sid       = "GrantTheIdentityKey"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.identity_keys.arn]
  }
  # What it starts on, and the secrets its document names. Read, never written: every parameter
  # of the installation is this module's to write (secrets.tf).
  statement {
    sid     = "ItsDocumentAndSecrets"
    actions = ["ssm:GetParameter"]
    resources = [for p in [local.config_parameter, local.installation_parameter, local.ca_parameter, local.admin_password_parameter] :
    "${local.arn}:ssm:${local.region}:${local.account}:parameter${p}"]
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
  # Every time the identity key was opened, as CloudTrail recorded it, to hold to the records of the
  # grants the control plane gave (spin's internal/identity/audit). LookupEvents takes no resource:
  # it reads the account's management events, which name no secret.
  statement {
    sid       = "ReadWhatTheKeySigned"
    actions   = ["cloudtrail:LookupEvents"]
    resources = ["*"]
  }
  # The bill, read: what the installation cost by day and service and what it is forecast to, which
  # the control plane keeps and shows. Cost Explorer takes no resource, so this reads the account's
  # whole bill; the control plane asks only for what carries its spin:installation tag. Read, never
  # changed: nothing here may make, move or delete a budget or a cost category.
  statement {
    sid       = "ReadTheBill"
    actions   = ["ce:GetCostAndUsage", "ce:GetCostForecast"]
    resources = ["*"]
  }
  dynamic "statement" {
    for_each = aws_budgets_budget.monthly
    content {
      sid       = "ReadItsBudget"
      actions   = ["budgets:ViewBudget"]
      resources = [statement.value.arn]
    }
  }
  # Its group of one: in service once it leads, and to be replaced when it stays down.
  statement {
    sid = "ItsGroup"
    actions = ["autoscaling:CompleteLifecycleAction", "autoscaling:RecordLifecycleActionHeartbeat",
    "autoscaling:SetInstanceHealth"]
    resources = ["${local.arn}:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.controlplane_group}"]
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
  name                 = "${local.iam_name}-runner-scope"
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
  # Who wrote a volume's HEAD: a writer's record, read to hold the HEAD's signature to before a
  # restore believes it. Written by the control plane alone, at a host's join.
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.volumes.arn}/writers/*"]
  }
  # The identity a host signs for its machines (spin's internal/runner/identityserver): the record
  # of each - under the host's own name, as the session policy narrows it - and the X.509 CA the
  # first host to sign an SVID makes; and the keyrings and rosters people signed, which it holds a
  # workspace's creation to, read and never written.
  statement {
    actions = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.volumes.arn}/identity/issued/*",
    "${aws_s3_bucket.volumes.arn}/identity/x509-ca.der"]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.volumes.arn}/rosters/*"]
  }
  # Every version of each workspace's access, which a host reads the newest of at every login
  # (spin's ownerword.Newest): read and never written - the control plane writes them.
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.volumes.arn}/access/*"]
  }
}

resource "aws_iam_role_policy" "runner_scope" {
  name   = "spin"
  role   = aws_iam_role.runner_scope.id
  policy = data.aws_iam_policy_document.runner_scope.json
}
