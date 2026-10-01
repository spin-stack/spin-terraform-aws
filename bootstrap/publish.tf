# Where Spin OS is published from GitHub Actions rather than from somebody's machine: each
# repository named here (spin-stack/ami) gets a role, assumed with GitHub's OIDC token, that builds
# an image of a release and registers it in this account - and nothing else.
#
#   <name>-publish  signs the image's kernel with the Secure Boot key in KMS, writes the disk into a
#                   snapshot over the EBS direct APIs, and registers the image. Only a job of that
#                   repository's `publish` environment, running on main, assumes it.
#
# The repository's OIDC subject carries the ref, as github.tf's do (the same `gh api` there).
#
# It registers and never deregisters: an installation's launch templates name an image by id,
# and one taken away is a group that can start no machine. The only thing it deletes is a snapshot
# a publish of its own made and failed to register - one carrying the build's commit tag.

variable "image_publishers" {
  description = "Repositories that publish Spin OS from GitHub Actions, as owner/name => the prefix of their OIDC subject (github.tf): each gets a publish role."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([for r, prefix in var.image_publishers :
    can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", r)) && startswith(prefix, "repo:")])
    error_message = "Each of image_publishers is owner/name => the repository's sub_claim_prefix, which starts with repo:."
  }
}

# The Secure Boot key each role's image is signed with: three, so an instance's PCR7 says which role
# it booted - a key the control plane's key policy, and later a join, can tell apart - and a runner's
# image can never boot as a control plane's. RSA-2048 signing PKCS #1 v1.5 over SHA-256, the one
# algorithm UEFI firmware and Authenticode agree on; the private halves never leave KMS. A new key
# is a new db that no image published before trusts, so a plan never destroys one.
locals {
  secure_boot_roles = toset(["control-plane", "runner", "proxy"])
}

resource "aws_kms_key" "secure_boot" {
  for_each                 = local.secure_boot_roles
  description              = "Signs the kernel image of Spin OS's ${each.key} image (Secure Boot db)"
  customer_master_key_spec = "RSA_2048"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 30
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "secure_boot" {
  for_each      = local.secure_boot_roles
  name          = "alias/spin-os-secureboot-db-${each.key}"
  target_key_id = aws_kms_key.secure_boot[each.key].key_id
}

output "secure_boot_keys" {
  description = "Each role's Secure Boot key, by the alias spin-stack/ami signs that role's image with."
  value       = { for role, a in aws_kms_alias.secure_boot : role => a.name }
}

locals {
  publishers = { for r, prefix in var.image_publishers : replace(r, "/", "-") => prefix }
  arn        = "arn:${data.aws_partition.current.partition}"
}

# The provider is made here too when no repository applies an installation from GitHub Actions.
resource "aws_iam_openid_connect_provider" "publish" {
  count          = length(var.image_publishers) > 0 && length(var.github_repositories) == 0 ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_oidc = one(concat(aws_iam_openid_connect_provider.github[*].arn, aws_iam_openid_connect_provider.publish[*].arn))
}

data "aws_iam_policy_document" "publish_trust" {
  for_each = local.publishers
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${each.value}:environment:publish:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "publish" {
  for_each             = local.publishers
  name                 = "${each.key}-publish"
  assume_role_policy   = data.aws_iam_policy_document.publish_trust[each.key].json
  max_session_duration = 3 * 3600
}

data "aws_iam_policy_document" "publish" {
  # The kernel image's signature: each role's key, and no other.
  statement {
    sid       = "SignTheKernel"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = [for k in aws_kms_key.secure_boot : k.arn]
  }
  # The disk, block by block, into a new snapshot, tagged as it is started.
  statement {
    sid       = "WriteTheSnapshot"
    actions   = ["ebs:StartSnapshot", "ebs:PutSnapshotBlock", "ebs:CompleteSnapshot"]
    resources = ["${local.arn}:ec2:${var.region}::snapshot/*"]
  }
  statement {
    sid       = "TagWhatItMakes"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.arn}:ec2:${var.region}::snapshot/*", "${local.arn}:ec2:${var.region}::image/*"]
  }
  statement {
    sid       = "SeeTheImages"
    actions   = ["ec2:DescribeImages", "ec2:DescribeSnapshots"]
    resources = ["*"]
  }
  statement {
    sid       = "RegisterTheImage"
    actions   = ["ec2:RegisterImage"]
    resources = ["${local.arn}:ec2:${var.region}::image/*", "${local.arn}:ec2:${var.region}::snapshot/*"]
  }
  # What a failed publish leaves: a snapshot its build tagged, and no other.
  statement {
    sid       = "DeleteWhatAFailedPublishLeft"
    actions   = ["ec2:DeleteSnapshot"]
    resources = ["${local.arn}:ec2:${var.region}::snapshot/*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/spin-os:commit"
      values   = ["false"]
    }
  }
}

resource "aws_iam_role_policy" "publish" {
  for_each = aws_iam_role.publish
  name     = "publish"
  role     = each.value.name
  policy   = data.aws_iam_policy_document.publish.json
}

output "publish_roles" {
  description = "For each repository that publishes Spin OS, the role its workflow assumes."
  value       = { for r, prefix in var.image_publishers : r => aws_iam_role.publish[replace(r, "/", "-")].arn }
}
