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
  # One role is ever assumed from another: the one the control plane mints runners'
  # credentials under. Nothing becomes anything else, or anyone federated.
  statement {
    sid           = "OnlyTheRunnerScope"
    effect        = "Deny"
    actions       = ["sts:AssumeRole"]
    not_resources = [local.runner_scope_arn]
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
      "arn:aws:ec2:${local.region}:${local.account}:elastic-ip/${aws_eip.proxy.allocation_id}",
      "arn:aws:ec2:${local.region}:${local.account}:instance/*",
      "arn:aws:ec2:${local.region}:${local.account}:network-interface/*",
    ]
  }
  # The control plane's secrets are its role's alone, whatever policy a role is given later: the
  # encryption key that opens the catalog's seals, and the collector's token. The parameters are
  # read under the account's aws/ssm key, which opens them to any principal SSM lets read them,
  # so this is where the line is. The pool's token is the runners' to read as well, and every
  # parameter here is the control plane's alone to write.
  statement {
    sid       = "TheControlPlanesSecrets"
    effect    = "Deny"
    actions   = ["ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter*", "ssm:LabelParameterVersion"]
    resources = [for p in [local.key_parameter, local.token_parameter_grafana] : "arn:aws:ssm:${local.region}:${local.account}:parameter${p}"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.controlplane_role_arn]
    }
  }
  statement {
    sid       = "ThePoolsToken"
    effect    = "Deny"
    actions   = ["ssm:GetParameter*"]
    resources = ["arn:aws:ssm:${local.region}:${local.account}:parameter${local.token_parameter}"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.controlplane_role_arn, local.runner_role_arn]
    }
  }
  statement {
    sid       = "OnlyTheControlPlaneWrites"
    effect    = "Deny"
    actions   = ["ssm:PutParameter", "ssm:DeleteParameter*", "ssm:LabelParameterVersion"]
    resources = ["${local.ssm_prefix}/*"]
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [local.controlplane_role_arn]
    }
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
      "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
      "cloudtrail:*", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "ec2:DeleteFlowLogs",
      # The catalog, and what would bring it back: a taken machine signs in to the database as
      # the control plane does, and no further.
      "rds:Delete*", "rds:Modify*", "rds:Reboot*", "rds:Stop*", "rds:RestoreDB*", "rds:CopyDBSnapshot",
      "rds:ModifyDBSnapshotAttribute",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.name}-boundary"
  description = "The most any role of the ${var.name} installation may do"
  policy      = data.aws_iam_policy_document.boundary.json
  tags        = local.tags
}
