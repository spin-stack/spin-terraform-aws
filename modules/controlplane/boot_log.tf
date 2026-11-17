# What each machine's boot says, kept after the machine is gone: a boot that fails abandons its
# launch, the group terminates the machine, and a log on its disk would go with it. One stream per
# role, step and instance (<role>/<step>/<instance-id>, spin's boot names it), so a role's machines
# are one prefix; the machines may add to streams and read nothing, and nothing but the retention
# removes what they wrote (the boundary refuses the rest).

# CloudWatch's own encryption and no KMS key: a boot says what it does, never a secret, and who
# reads it is IAM's.
#trivy:ignore:AWS-0017
resource "aws_cloudwatch_log_group" "boot" {
  name              = "/spin/${local.name}/boot"
  retention_in_days = var.log_retention_days
  tags              = merge(local.tags, { "spin:role" = "logs" })
}

# A policy per role, each its own prefix: a runner's credential, the one a tenant who escaped a
# machine is nearest to, writes no line into what the control plane's or the proxy's boot says.
# Not narrower than the role: no policy variable is the instance id alone, and the ones that carry
# it (aws:userid, ec2:SourceInstanceARN) hold a colon, which a stream's name may not.
data "aws_iam_policy_document" "boot_log" {
  for_each = toset(["control-plane", "proxy", "runner"])

  statement {
    sid       = "ItsRolesBoots"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.boot.arn}:log-stream:${each.key}/*"]
  }
}

resource "aws_iam_policy" "boot_log" {
  for_each = toset(keys(data.aws_iam_policy_document.boot_log))

  name        = "${local.iam_name}-${each.key}-boot-log"
  description = "Write a ${each.key} machine's boot to ${aws_cloudwatch_log_group.boot.name}, under ${each.key}/, and nothing else"
  policy      = data.aws_iam_policy_document.boot_log[each.key].json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "controlplane_boot_log" {
  role       = aws_iam_role.controlplane.name
  policy_arn = aws_iam_policy.boot_log["control-plane"].arn
}

resource "aws_iam_role_policy_attachment" "proxy_boot_log" {
  role       = aws_iam_role.proxy.name
  policy_arn = aws_iam_policy.boot_log["proxy"].arn
}

locals {
  # Where a machine's boot writes, as its document says it.
  boot_log = { aws = { region = local.region, group = aws_cloudwatch_log_group.boot.name } }
}
