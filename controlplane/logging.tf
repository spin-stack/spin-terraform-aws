# What crossed the VPC and what it looked up: the two records an incident is reconstructed
# from and nothing on the machines keeps. A flow log is every connection accepted or refused
# at a security group — the proxy's public 443, a runner reaching somewhere — and the
# resolver's log is every name the VPC resolved, a workspace's included, since each host's
# resolver asks this one. Both go to CloudWatch for log_retention_days and no longer.

resource "aws_cloudwatch_log_group" "flow" {
  count             = var.network_logs ? 1 : 0
  name              = "/spin/${var.name}/vpc-flow"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "resolver" {
  count             = var.network_logs ? 1 : 0
  name              = "/spin/${var.name}/resolver-queries"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_iam_role" "flow" {
  count                = var.network_logs ? 1 : 0
  name                 = "${var.name}-vpc-flow"
  assume_role_policy   = data.aws_iam_policy_document.flow_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

data "aws_iam_policy_document" "flow" {
  count = var.network_logs ? 1 : 0
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  count  = var.network_logs ? 1 : 0
  name   = "spin"
  role   = aws_iam_role.flow[0].id
  policy = data.aws_iam_policy_document.flow[0].json
}

resource "aws_flow_log" "vpc" {
  count                    = var.network_logs ? 1 : 0
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn             = aws_iam_role.flow[0].arn
  max_aggregation_interval = 600
  tags                     = local.tags
}

# The resolver writes with a resource policy on the group, held to this account's query-log
# configurations.
data "aws_iam_policy_document" "resolver" {
  count = var.network_logs ? 1 : 0
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.resolver[0].arn}:*"]
    principals {
      type        = "Service"
      identifiers = ["route53resolver.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:route53resolver:${local.region}:${local.account}:resolver-query-log-config/*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "resolver" {
  count           = var.network_logs ? 1 : 0
  policy_name     = "${var.name}-resolver-queries"
  policy_document = data.aws_iam_policy_document.resolver[0].json
}

resource "aws_route53_resolver_query_log_config" "this" {
  count           = var.network_logs ? 1 : 0
  name            = var.name
  destination_arn = aws_cloudwatch_log_group.resolver[0].arn
  tags            = local.tags
  depends_on      = [aws_cloudwatch_log_resource_policy.resolver]
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  count                        = var.network_logs ? 1 : 0
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this[0].id
  resource_id                  = aws_vpc.this.id
}
