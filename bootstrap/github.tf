# An installation applied from GitHub Actions rather than from somebody's machine: each repository
# named here gets two roles, assumed with GitHub's OIDC token, so no key is kept in GitHub.
#
#   <name>-plan   a pull request's plan: read everything, open the state, write nothing. Only a
#                 pull_request run of that repository assumes it, and it plans with -lock=false,
#                 since it may not take the state's lock.
#   <name>-apply  the apply: anything an installation makes. Only a job of that repository's
#                 `production` environment, running on main, assumes it.
#
# Which branch a token was issued for is only in its subject once the repository says so - GitHub's
# default subject names the environment and not the ref - so each repository sets its subject to
# carry the ref, and gives this its prefix:
#
#   gh api -X PUT repos/<owner>/<name>/actions/oidc/customization/sub \
#     -F use_default=false -f 'include_claim_keys[]=repo' -f 'include_claim_keys[]=context' -f 'include_claim_keys[]=ref'
#   gh api repos/<owner>/<name>/actions/oidc/customization/sub --jq .sub_claim_prefix
#
# Both roles open the state, and the state holds the installation's CA key: whoever may open a
# pull request in the repository may read it. Keep the repository to the people who administer
# the installation.

variable "github_repositories" {
  description = "Repositories that apply an installation from GitHub Actions, as owner/name => the prefix of their OIDC subject (sub_claim_prefix, above): each gets a plan role and an apply role."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([for r, prefix in var.github_repositories :
    can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", r)) && startswith(prefix, "repo:")])
    error_message = "Each of github_repositories is owner/name => the repository's sub_claim_prefix, which starts with repo:."
  }
}

locals {
  github = { for r, prefix in var.github_repositories : replace(r, "/", "-") => { repo = r, prefix = prefix } }
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = length(var.github_repositories) > 0 ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = { for pair in setproduct(keys(local.github), ["plan", "apply"]) : "${pair[0]}-${pair[1]}" => { prefix = local.github[pair[0]].prefix, role = pair[1] } }
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [each.value.role == "plan" ?
        "${each.value.prefix}:pull_request:ref:refs/pull/*/merge" :
      "${each.value.prefix}:environment:production:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each             = data.aws_iam_policy_document.github_trust
  name                 = "${each.key}-tofu"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# Plans read the account and open the state; an apply may do anything an installation makes -
# roles, a network, a database - which is most of an account.
resource "aws_iam_role_policy_attachment" "github" {
  for_each   = aws_iam_role.github
  role       = each.value.name
  policy_arn = endswith(each.key, "-plan") ? "arn:aws:iam::aws:policy/ReadOnlyAccess" : "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ReadOnlyAccess reads no SecureString and opens no state: the key that encrypts the state, and
# the account's SSM key through SSM alone, which a plan's refresh of the installation's parameters
# needs.
data "aws_iam_policy_document" "plan_opens" {
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "plan_opens" {
  for_each = { for k, r in aws_iam_role.github : k => r if endswith(k, "-plan") }
  name     = "opens-the-state"
  role     = each.value.name
  policy   = data.aws_iam_policy_document.plan_opens.json
}

output "github_roles" {
  description = "For each repository, the roles its workflow assumes: AWS_PLAN_ROLE and AWS_APPLY_ROLE."
  value = { for k, r in local.github : r.repo => {
    plan  = aws_iam_role.github["${k}-plan"].arn
    apply = aws_iam_role.github["${k}-apply"].arn
  } }
}
