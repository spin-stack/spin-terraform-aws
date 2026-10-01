# The control plane's encryption key - which opens everything its database seals - is made at every
# start, and only by a machine that proves the image it booted (spin's
# internal/installation/attestedkey). It is an ECDH secret between this KMS key and a fixed peer,
# which KMS answers through DeriveSharedSecret only to a NitroTPM attestation document whose PCRs
# are this release's image's, and then encrypted to a key only that machine holds. Nothing stores
# the key: not SSM, not this state, not a ciphertext of it. This apply never sees it.
#
# So the key is this KMS key: a new one is a database nothing can open, which is why it is never
# destroyed by a plan.

locals {
  # Each release's PCRs, role by role, as spin-stack/ami's publish proposes them beside its images
  # (images.json).
  measurements = jsondecode(file("${path.module}/../../measurements.json"))
  # Those of each role's image this installation boots: a build of your own names its own, and so
  # may a release published before its PCRs were. Each role's image measures its own PCRs - it is
  # signed by its own key - so the control plane's key is answered to the control plane's alone,
  # and a host joins only as the runner's.
  pcrs_of = { for role in ["control-plane", "runner"] : role => (
    var.image_measurements != null ? var.image_measurements[role] :
    length(var.image_ids) > 0 ? null : try(local.measurements[var.spin_version][role], null)
  ) }
  image_pcrs = local.pcrs_of["control-plane"]
}

# No rotation: KMS rotates no asymmetric key, and a new key-agreement key would be a new secret and
# a database nothing can open. A rotation of the control plane's key is a new peer label in spin.
#trivy:ignore:AWS-0065
resource "aws_kms_key" "encryption" {
  description              = "${local.name}: agrees the control plane's encryption key with an attested machine"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "KEY_AGREEMENT"
  deletion_window_in_days  = 30
  policy                   = data.aws_iam_policy_document.encryption_key.json
  tags                     = local.tags
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = local.image_pcrs != null
      error_message = length(var.image_ids) > 0 ? "image_ids names images of your own: image_measurements are their PCRs, and the control plane's are what its key is answered to." : "${var.spin_version} has no measurements of its control plane's image in measurements.json: a machine of it could not attest, and the control plane would have no key. Publish it (spin-stack/ami) and move this module's ref, or give its manifest's PCRs as image_measurements."
    }
  }
}

resource "aws_kms_alias" "encryption" {
  name          = "alias/spin-${local.name}-encryption"
  target_key_id = aws_kms_key.encryption.key_id
}

# No statement answers the key to anything but an attested control plane - not the account, not an
# IAM policy: a key policy that let IAM grant DeriveSharedSecret would let any principal it is
# granted to have the secret in the clear, with no attestation at all.
data "aws_iam_policy_document" "encryption_key" {
  # The account keeps the key: who may see it, change its policy, tag or delete it. Not use it.
  statement {
    sid    = "TheAccountKeepsTheKey"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account}:root"]
    }
    actions = [
      "kms:Describe*", "kms:List*", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:GetPublicKey",
      "kms:PutKeyPolicy", "kms:TagResource", "kms:UntagResource", "kms:CreateAlias", "kms:UpdateAlias",
      "kms:DeleteAlias", "kms:EnableKey", "kms:DisableKey", "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion", "kms:UpdateKeyDescription",
    ]
    resources = ["*"]
  }
  # The control plane's role, from a machine whose NitroTPM reports this release's image: its
  # kernel and command line (PCR4, PCR12) and the Secure Boot keys that checked them (PCR7).
  statement {
    sid    = "OnlyAnAttestedControlPlane"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    actions   = ["kms:DeriveSharedSecret"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:KeyAgreementAlgorithm"
      values   = ["ECDH"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR4"
      values   = [try(local.image_pcrs.pcr4, "none")]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR7"
      values   = [try(local.image_pcrs.pcr7, "none")]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:RecipientAttestation:NitroTPMPCR12"
      values   = [try(local.image_pcrs.pcr12, "none")]
    }
  }
  # And whatever a later edit of this policy allows, never without an attestation document: the
  # secret in the clear is the installation.
  statement {
    sid    = "NeverWithoutAttestation"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:DeriveSharedSecret"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "kms:RecipientAttestation:NitroTPMPCR7"
      values   = ["true"]
    }
  }
}
