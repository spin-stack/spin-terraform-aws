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
  # Each release's builds, role by role and revision by revision, as spin-stack/ami's publish
  # proposes them beside its images (images.json): { release: { role: { "r<N>": build } } }.
  measurements = jsondecode(file("${path.module}/../../measurements.json"))
  # Each role's builds of this release, oldest first: a release is built again when what is under
  # spin moves - a kernel, a package - and each build is a revision, r1, r2 and on. Images of your
  # own name their own (image_measurements), as may a release published before its PCRs were. Each
  # role's image measures its own PCRs - it is signed by its own key - so the control plane's key is
  # answered to the control plane's builds alone, a host joins only as the runner's, and the proxy
  # is given its token only as the proxy's.
  builds_of = { for role in local.roles : role => (
    var.image_measurements != null ? var.image_measurements[role] :
    length(var.image_ids) > 0 ? [] : [
      # Zero-padded, so r10 sorts after r9.
      for n in sort([for r in keys(try(local.measurements[var.spin_version][role], {})) : format("%06d", tonumber(trimprefix(r, "r")))]) :
      local.measurements[var.spin_version][role]["r${tonumber(n)}"]
    ]
  ) }
  # The builds a machine of each role may prove it booted: every one not revoked, so a machine of an
  # earlier build still running when a later one is published goes on until it is replaced.
  trusted_of = { for role, builds in local.builds_of : role => [for b in builds : b if try(b.revoked == null || b.revoked == "", true)] }
  # The PCRs alone: what the KMS key policies and the proxy's join hold a machine to, a set each.
  pcrs_of = { for role, builds in local.trusted_of : role => [for b in builds : { for pcr in ["pcr4", "pcr7", "pcr12"] : pcr => b[pcr] }] }
  # A writer's builds - the runner's, the control plane's - with what their release signed of each:
  # the statement of its PCRs and the bundle that signs it, which a writer's record carries for a
  # verifier to hold the machine's document to (spin F6b). Its image's own publisher signs it, so a
  # control plane that is told other PCRs is not believed by a verifier.
  signed_of = { for role in ["control-plane", "runner"] : role => [
    for b in local.trusted_of[role] : { for k in ["pcr4", "pcr7", "pcr12", "statement", "bundle"] : k => try(b[k], null) }
  ] }
  # The newest build of each role is the image this installation boots - images.json's, as the last
  # publish proposed it, or image_ids' - and one spin-stack/ami marked revoked in measurements.json,
  # with why (task images:revoke), is a release not installed: an installation on it is told on its
  # next plan. An entry with no revocation has it null - an optional attribute - or not at all.
  revoked = { for role, builds in local.builds_of : role => builds[length(builds) - 1].revoked
  if length(builds) > 0 && try(builds[length(builds) - 1].revoked != null && builds[length(builds) - 1].revoked != "", false) }
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
      condition     = length(local.revoked) == 0
      error_message = "${var.spin_version} is revoked, and is not installed: ${join("; ", [for role, why in local.revoked : "the newest build of its ${role} image: ${why}"])}. Move this module's spin_version to a release that is not, or publish a build of it that replaces the revoked one."
    }
    precondition {
      condition     = length(local.pcrs_of["control-plane"]) > 0
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
  # The control plane's role, from a machine whose NitroTPM reports a build of this release's image:
  # its kernel and command line (PCR4, PCR12) and the Secure Boot keys that checked them (PCR7). A
  # statement per build, its three PCRs together: one build's PCR4 with another's PCR12 is no image.
  dynamic "statement" {
    for_each = local.pcrs_of["control-plane"]
    content {
      sid    = "OnlyAnAttestedControlPlane${statement.key + 1}"
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
        values   = [statement.value.pcr4]
      }
      condition {
        test     = "StringEquals"
        variable = "kms:RecipientAttestation:NitroTPMPCR7"
        values   = [statement.value.pcr7]
      }
      condition {
        test     = "StringEquals"
        variable = "kms:RecipientAttestation:NitroTPMPCR12"
        values   = [statement.value.pcr12]
      }
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
