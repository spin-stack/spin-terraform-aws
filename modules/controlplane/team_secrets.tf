# A team may keep a secret its workspaces' brokered requests carry in Secrets Manager rather than
# in the control plane's database (spin's internal/installation/provider/aws/secretrefs): the
# control plane reads it when a host asks, in a session of this role tagged spin-team-id with the
# team whose secret it is. The session reads only a secret tagged the same, so a team's admin who
# names another team's secret, or the installation's, is refused by Secrets Manager.
#
# This holds against a confused deputy, not against a control plane that was taken: it tags the
# session, and holds what it reads in the clear. Whoever may tag a secret spin-team-id in the
# account hands it to that team.

locals {
  team_secrets_role_arn = "${local.arn}:iam::${local.account}:role/${local.iam_name}-team-secrets"
}

# Assumed by the control plane alone, and only tagged with the team a read is for.
data "aws_iam_policy_document" "team_secrets_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controlplane.arn]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/spin-team-id"
      values   = ["false"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["spin-team-id"]
    }
  }
}

# A secret of the account's, read, and only one tagged with the session's team. A secret under a
# customer-managed key is also that key's policy to open.
data "aws_iam_policy_document" "team_secrets" {
  statement {
    sid       = "TheTeamsOwnSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["${local.arn}:secretsmanager:*:${local.account}:secret:*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/spin-team-id"
      values   = ["$${aws:PrincipalTag/spin-team-id}"]
    }
  }
}

resource "aws_iam_role" "team_secrets" {
  name                 = "${local.iam_name}-team-secrets"
  assume_role_policy   = data.aws_iam_policy_document.team_secrets_trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

resource "aws_iam_role_policy" "team_secrets" {
  name   = "spin"
  role   = aws_iam_role.team_secrets.id
  policy = data.aws_iam_policy_document.team_secrets.json
}
