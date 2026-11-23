# The machines' own EBS disks - the control plane's, the proxy's and every runner's - are encrypted
# under this key rather than the account's aws/ebs, which any principal of the account that may use
# EBS may use. Every one of those machines is started by an Auto Scaling group, the runners' by the
# groups the control plane makes, so the one principal that uses the key is Auto Scaling's
# service-linked role: it makes the disks and grants EC2 the key for them.
#
# Not spin's volumes (volume_keys.tf): what a disk holds ends with its machine, so a new key is new
# disks on the next machines, and a plan may replace it.

locals {
  # Named by condition, not as a principal: KMS refuses a policy naming a role that does not exist,
  # and an account has none until its first Auto Scaling group, which here is made after this key.
  autoscaling_role_arn = "${local.arn}:iam::${local.account}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
}

resource "aws_kms_key" "disks" {
  description             = "${local.name}: encrypts the control plane's, the proxy's and the runners' EBS disks"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.disks.json
  tags                    = merge(local.tags, { "spin:role" = "disks" })
}

resource "aws_kms_alias" "disks" {
  name          = "alias/spin-${local.name}-disks"
  target_key_id = aws_kms_key.disks.key_id
}

data "aws_iam_policy_document" "disks" {
  # The account keeps the key: who may see it, change its policy, tag or delete it. Not use it.
  statement {
    sid    = "TheAccountKeepsTheKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account}:root"]
    }
    actions = [
      "kms:Describe*", "kms:List*", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus",
      "kms:PutKeyPolicy", "kms:TagResource", "kms:UntagResource", "kms:CreateAlias", "kms:UpdateAlias",
      "kms:DeleteAlias", "kms:EnableKey", "kms:DisableKey", "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion", "kms:UpdateKeyDescription", "kms:EnableKeyRotation",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "AutoScalingMakesTheDisks"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.autoscaling_role_arn]
    }
  }
  # What lets the machine read its disk: a grant to EC2 for that disk, which EC2 retires with it.
  statement {
    sid    = "AutoScalingGrantsEC2TheDisks"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.autoscaling_role_arn]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}
