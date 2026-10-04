# The key the installation's workspaces' identity is signed with (spin's internal/identity), which
# the control plane never holds and never signs with. KMS makes it once, for the control plane,
# without its plaintext: an ECDSA P-256 data key pair whose private half KMS answers only
# encrypted under this key (spin's internal/installation/provider/aws/identitykeys). The control
# plane keeps that in its bucket and grants it to hosts - the sealed key and a session of the
# identity-keys role - and the session decrypts it only answered to a NitroTPM attestation document
# whose PCRs are the runner's image's. Each runner signs its own workspaces' identities.
#
# KMS cannot hold a signature to an attestation - kms:RecipientAttestation is a condition of
# Decrypt and its kin, never of Sign - which is why the key is released to a host rather than
# signed with in KMS.
#
# A new key is every relying party's trust in the old one gone, and the published key set
# (modules/identity-issuer) is written from the one the control plane keeps: it is never destroyed
# by a plan.
variable "identity_record_days" {
  description = "How many days the record of each identity a host signs is kept (identity/issued/ in the volumes bucket): longer than the bucket's lock, and long enough to answer who took an identity when."
  type        = number
  default     = 400
  validation {
    condition     = var.identity_record_days > var.object_lock_days
    error_message = "identity_record_days is longer than object_lock_days: the lock keeps a record at least that long anyway."
  }
}

locals {
  # The context the key is made under, which every use of it is held to.
  identity_purpose = "identity-issuer"
}

#trivy:ignore:AWS-0065
resource "aws_kms_key" "identity" {
  description             = "${local.name}: seals its identity key, which only an attested runner opens"
  deletion_window_in_days = 30
  # KMS keeps every version of the key it rotated from: the sealed identity key keeps opening.
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.identity_key.json
  tags                = merge(local.tags, { "spin:role" = "identity" })
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "identity" {
  name          = "alias/spin-${local.name}-identity"
  target_key_id = aws_kms_key.identity.key_id
}

data "aws_iam_policy_document" "identity_key" {
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
  # The identity key, made once, which the control plane never sees: a P-256 pair under the
  # identity's context, its private half answered encrypted only.
  statement {
    sid    = "TheControlPlaneMakesTheKeyUnseen"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:GenerateDataKeyPairWithoutPlaintext"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:DataKeyPairSpec"
      values   = ["ECC_NIST_P256"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:spin:purpose"
      values   = [local.identity_purpose]
    }
  }
  # A grant: a session of the identity-keys role decrypts the key, in its context, answered to a
  # runner of this release's image - its kernel and command line (PCR4, PCR12) and the Secure Boot
  # keys that checked them (PCR7).
  statement {
    sid    = "OnlyAnAttestedRunnerOpensTheKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.identity_keys.arn]
    }
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:spin:purpose"
      values   = [local.identity_purpose]
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
  # Whatever a later edit of this policy allows, never the key in the clear: a decrypt with no
  # attestation document is every workspace's identity.
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
  # And never by the control plane's role, attested or not: it neither opens the key nor makes one
  # it knows - a pair with its plaintext, a ciphertext of its own, one re-encrypted from elsewhere.
  statement {
    sid    = "NeverTheControlPlane"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyPair",
    "kms:GenerateDataKeyWithoutPlaintext", "kms:ReEncryptFrom", "kms:ReEncryptTo"]
    resources = ["*"]
  }
}

# Assumed by the control plane alone, untagged: the key is one, and so is what may open it.
data "aws_iam_policy_document" "identity_keys_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
  }
}

# Its only permission is the key policy's: nothing is attached to it.
resource "aws_iam_role" "identity_keys" {
  name                 = "${local.iam_name}-identity-keys"
  assume_role_policy   = data.aws_iam_policy_document.identity_keys_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}
