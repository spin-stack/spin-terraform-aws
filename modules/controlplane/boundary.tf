# The most any role of the installation may ever do, whatever is attached to it later: a
# permissions boundary on every role both modules make. Each role's own policy is what it may
# do; this is what nobody can grant it, by mistake or from a machine that was taken - a role
# that writes IAM makes itself any role, one that edits the network opens the control plane to
# the internet, and one that runs commands through SSM is on every other machine.

data "aws_iam_policy_document" "boundary" {
  # A boundary caps; the role's own policy grants. Without this, nothing would be allowed.
  statement {
    sid       = "WhatTheRoleItselfGrants"
    actions   = ["*"]
    resources = ["*"]
  }
  statement {
    sid    = "NoIAM"
    effect = "Deny"
    actions = [
      "iam:Add*", "iam:Attach*", "iam:Change*", "iam:Create*", "iam:Deactivate*", "iam:Delete*",
      "iam:Detach*", "iam:Enable*", "iam:PassRole", "iam:Put*", "iam:Remove*", "iam:Reset*",
      "iam:Resync*", "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
      "organizations:*", "account:*",
    ]
    resources = ["*"]
  }
  # Two roles are ever assumed from another: the one the control plane mints runners'
  # credentials under, and the one it grants volumes' keys under. Nothing becomes anything
  # else, or anyone federated.
  statement {
    sid           = "OnlyTheRunnerScopeAndTheVolumeKeys"
    effect        = "Deny"
    actions       = ["sts:AssumeRole"]
    not_resources = [local.runner_scope_arn, local.volume_keys_role_arn]
  }
  statement {
    sid    = "NoOtherCredentials"
    effect = "Deny"
    actions = [
      "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity", "sts:GetFederationToken",
      "sts:GetSessionToken",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "NotTheNetwork"
    effect = "Deny"
    actions = [
      "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*Route*", "ec2:*Gateway*", "ec2:*NetworkAcl*",
      "ec2:*SecurityGroup*", "ec2:*NetworkInterface*", "ec2:*Dhcp*",
      "ec2:*Vpn*", "ec2:ModifyInstanceAttribute", "ec2:ModifyInstanceMetadataOptions",
      "elasticloadbalancing:*",
    ]
    resources = ["*"]
  }
  # The two pieces of the network a machine moves to itself when it replaces another: its name
  # in the installation's own zone, and the proxy's one address. Nothing of any other zone or
  # address, whatever a role is given.
  statement {
    sid           = "OnlyTheInstallationsZone"
    effect        = "Deny"
    actions       = ["route53:*"]
    not_resources = [aws_route53_zone.internal.arn]
  }
  statement {
    sid     = "OnlyTheProxysAddress"
    effect  = "Deny"
    actions = ["ec2:*Address*"]
    not_resources = [
      "${local.arn}:ec2:${local.region}:${local.account}:elastic-ip/${aws_eip.proxy.allocation_id}",
      "${local.arn}:ec2:${local.region}:${local.account}:instance/*",
      "${local.arn}:ec2:${local.region}:${local.account}:network-interface/*",
    ]
  }
  # The control plane's secrets are its role's alone, whatever policy a role is given later: the
  # encryption key that opens the database's seals, the CA's key, the first administrator's
  # password, and the installation's configuration, which may say whom it
  # registers. The parameters are read under the account's aws/ssm key, which opens them to any
  # principal SSM lets read them, so this is where the line is.
  statement {
    sid     = "TheControlPlanesSecrets"
    effect  = "Deny"
    actions = ["ssm:GetParameter*"]
    resources = [for p in [local.ca_parameter, local.admin_password_parameter, local.installation_parameter] :
    "${local.arn}:ssm:${local.region}:${local.account}:parameter${p}"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.controlplane_role_arn]
    }
  }
  # No machine writes a parameter. What a machine reads is what an apply wrote, so a machine that
  # was taken cannot leave a value for the next one to start on - which is what a control plane
  # publishing a CA and a token for runners was.
  statement {
    sid       = "NoMachineWritesAParameter"
    effect    = "Deny"
    actions   = ["ssm:PutParameter", "ssm:DeleteParameter*", "ssm:LabelParameterVersion", "ssm:AddTagsToResource"]
    resources = ["*"]
  }
  # The machines are reached by a person through Session Manager; a role is never the one
  # starting a session or running a command on another.
  statement {
    sid       = "NoCommandsOnOtherMachines"
    effect    = "Deny"
    actions   = ["ssm:SendCommand", "ssm:StartSession", "ssm:StartAutomationExecution", "ec2-instance-connect:*"]
    resources = ["*"]
  }
  statement {
    sid    = "NotTheLocks"
    effect = "Deny"
    actions = [
      "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock",
      "s3:PutAccountPublicAccessBlock", "s3:BypassGovernanceRetention",
      "s3:PutBucketObjectLockConfiguration", "s3:DeleteBucket",
      # A bucket's lifecycle expires what it holds without an object being touched; the
      # installation declares it, and no role this boundary bounds writes one.
      "s3:PutLifecycleConfiguration", "s3:PutBucketVersioning",
      "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
      "cloudtrail:*", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "ec2:DeleteFlowLogs",
    ]
    resources = ["*"]
  }
  # The database's archive is the database: whoever writes it decides what a restore brings back,
  # who administers the installation among it. The control plane's role alone reaches it.
  statement {
    sid       = "TheDatabasesArchiveIsTheControlPlanes"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.database.arn, "${aws_s3_bucket.database.arn}/*"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.controlplane_role_arn]
    }
  }
  # And not even it erases a version: what a delete or an overwrite left is there to undo it until
  # the bucket's lifecycle expires it, whatever policy the role is given later.
  statement {
    sid       = "NoVersionOfTheArchiveErased"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.database.arn}/*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${local.iam_name}-boundary"
  description = "The most any role of the ${local.name} installation in ${local.region} may do"
  policy      = data.aws_iam_policy_document.boundary.json
  tags        = local.tags
}
