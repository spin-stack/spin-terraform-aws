# Every volume's key, and every checkpoint's, is a data key under this KMS key (spin's
# internal/installation/provider/aws/volumekeys). The control plane makes them without seeing them,
# checks them without opening them, and grants a host the wrapped key and a session of the
# volume-keys role tagged with the key's owner. That session decrypts that owner's keys alone, and
# only answered to a NitroTPM attestation document whose PCRs are the runner's image's: the control
# plane holds the session too, and is a machine of another image. Nobody else decrypts - not the
# control plane's role, not the account: the break-glass is nobody.
#
# So the key is every volume: it is never destroyed by a plan.

locals {
  volume_keys_role_arn = "${local.arn}:iam::${local.account}:role/${local.iam_name}-volume-keys"
  runner_pcrs          = local.pcrs_of["runner"]
}

#trivy:ignore:AWS-0065
resource "aws_kms_key" "volumes" {
  description             = "${local.name}: wraps every volume's key, which only an attested runner opens"
  deletion_window_in_days = 30
  # KMS keeps every version of the key it rotated from: a rotation leaves every wrapped key opening.
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.volume_keys.json
  tags                = merge(local.tags, { "spin:role" = "volumes" })
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "volumes" {
  name          = "alias/spin-${local.name}-volumes"
  target_key_id = aws_kms_key.volumes.key_id
}

data "aws_iam_policy_document" "volume_keys" {
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
  # A key for a volume or a checkpoint, which the control plane never sees: bound to its owner and
  # its version, and to nothing else.
  statement {
    sid    = "TheControlPlaneMakesKeys"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:GenerateDataKeyWithoutPlaintext"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "kms:EncryptionContext:spin:owner"
      values   = ["false"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "kms:EncryptionContextKeys"
      values   = ["spin:owner", "spin:key-version"]
    }
  }
  # The key of what the control plane seals itself - an image, an extension release - which it sees,
  # and whose context says so: what CloudTrail records tells the platform's keys from a tenant's.
  statement {
    sid    = "TheControlPlaneSeesWhatItSeals"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:GenerateDataKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:spin:held"
      values   = ["true"]
    }
  }
  # A wrapped key is checked by re-encrypting it under this same key, which proves it is this
  # key's without opening it. Never onto another key.
  statement {
    sid    = "TheControlPlaneChecksKeys"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:ReEncryptFrom", "kms:ReEncryptTo"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:ReEncryptOnSameKey"
      values   = ["true"]
    }
  }
  # A grant: a session of the volume-keys role, tagged with the owner, decrypts that owner's keys,
  # answered to a runner of this release's image - its kernel and command line (PCR4, PCR12) and
  # the Secure Boot keys that checked them (PCR7).
  statement {
    sid    = "OnlyAnAttestedRunnerOpensAKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.volume_keys.arn]
    }
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:spin:owner"
      values   = ["$${aws:PrincipalTag/spin:owner}"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR4"
      values   = [try(local.runner_pcrs.pcr4, "none")]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR7"
      values   = [try(local.runner_pcrs.pcr7, "none")]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR12"
      values   = [try(local.runner_pcrs.pcr12, "none")]
    }
  }
  # Whatever a later edit of this policy allows, never a key in the clear: a decrypt with no
  # attestation document is the volume.
  statement {
    sid    = "NeverWithoutAttestation"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "kms:RecipientAttestation:NitroTPMPCR7"
      values   = ["true"]
    }
  }
  # And never by the control plane's role, attested or not.
  statement {
    sid    = "NeverTheControlPlane"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }
}

# Assumed by the control plane alone, and only tagged with the owner a grant is for: a session
# tagged with nothing, or with anything else, is not made.
data "aws_iam_policy_document" "volume_keys_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/spin:owner"
      values   = ["false"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["spin:owner"]
    }
  }
}

# Its only permission is the key policy's: nothing is attached to it.
resource "aws_iam_role" "volume_keys" {
  name                 = "${local.iam_name}-volume-keys"
  assume_role_policy   = data.aws_iam_policy_document.volume_keys_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}
