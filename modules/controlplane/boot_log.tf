# What each machine's boot says, kept after the machine is gone: a boot that fails abandons its
# launch, the group terminates the machine, and a log on its disk would go with it. One stream per
# instance; the machines may add to their own streams and read nothing, and nothing but the
# retention removes what they wrote (the boundary refuses the rest).

resource "aws_cloudwatch_log_group" "boot" {
  name              = "/${var.name}/boot"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "boot_log" {
  statement {
    sid       = "ItsBootsLog"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.boot.arn}:log-stream:*"]
  }
}

resource "aws_iam_policy" "boot_log" {
  name        = "${var.name}-boot-log"
  description = "Write a machine's boot to ${aws_cloudwatch_log_group.boot.name}, and nothing else"
  policy      = data.aws_iam_policy_document.boot_log.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "controlplane_boot_log" {
  role       = aws_iam_role.controlplane.name
  policy_arn = aws_iam_policy.boot_log.arn
}

resource "aws_iam_role_policy_attachment" "proxy_boot_log" {
  role       = aws_iam_role.proxy.name
  policy_arn = aws_iam_policy.boot_log.arn
}

locals {
  # Where a machine's boot writes, as its document says it.
  boot_log = { aws = { region = local.region, group = aws_cloudwatch_log_group.boot.name } }
}
