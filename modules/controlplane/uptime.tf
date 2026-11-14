# Whoever security_emails names is told when the control plane is down, by something outside it:
# every other alert of an installation is Grafana's, and Grafana runs on the control plane, so a
# control plane that never came up told nobody. Two watches, each mailing when it fails and again
# when it recovers:
#
# - Route 53 asks https://app.<domain>/ready through the proxy, which answers 200 only from the
#   control plane that holds the term and reaches its database (spin's internal/controlplane/app).
#   A machine that runs while its services never came up fails this one.
# - EC2's status checks of the control plane's machine, which fail with the machine itself.
#
# A health check's metric is published in us-east-1 alone, and an alarm acts only on a topic in
# its own region: that alarm and the topic it mails are made there, whatever region the
# installation is in, and the people security_emails names confirm that topic once too.

locals {
  # The fewest regions Route 53 checks from. Each has its own two published networks, which a proxy
  # closed to everyone else lets in.
  health_check_regions = ["us-east-1", "us-west-2", "eu-west-1"]
  health_check_metrics = "us-east-1"
  proxy_open_to_all    = contains(var.proxy_allowed_cidrs, "0.0.0.0/0")
}

# HTTPS, which Route 53 does not hold to the certificate: it is the answer that is checked. Over
# HTTP the proxy answers a redirect whether or not the control plane serves, and that is healthy.
resource "aws_route53_health_check" "controlplane" {
  fqdn              = "app.${var.domain}"
  type              = "HTTPS"
  port              = 443
  resource_path     = "/ready"
  enable_sni        = true
  request_interval  = 30
  failure_threshold = 3
  regions           = local.health_check_regions
  tags              = merge(local.tags, { Name = "${local.name}-controlplane", "spin:role" = "alerts" })
}

data "aws_ip_ranges" "health_checks" {
  count    = local.proxy_open_to_all ? 0 : 1
  services = ["route53_healthchecks"]
  regions  = local.health_check_regions
}

resource "aws_vpc_security_group_ingress_rule" "proxy_https_health_checks" {
  for_each          = toset(local.proxy_open_to_all ? [] : data.aws_ip_ranges.health_checks[0].cidr_blocks)
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Route 53 health checks"
}

# AWS's own key cannot be used here: CloudWatch may not read it, and nothing secret is sent.
#trivy:ignore:AWS-0095
resource "aws_sns_topic" "controlplane_down" {
  region = local.health_check_metrics
  name   = "${local.iam_name}-controlplane-down"
  tags   = merge(local.tags, { "spin:role" = "alerts" })
}

resource "aws_sns_topic_subscription" "controlplane_down" {
  for_each  = toset(var.security_emails)
  region    = local.health_check_metrics
  topic_arn = aws_sns_topic.controlplane_down.arn
  protocol  = "email"
  endpoint  = each.value
}

# Two minutes unhealthy after the three failed checks that make it so: an update's handover, a
# term moving between two machines, is over well within that.
resource "aws_cloudwatch_metric_alarm" "controlplane_unreachable" {
  region              = local.health_check_metrics
  alarm_name          = "${local.iam_name}-controlplane-unreachable"
  alarm_description   = "https://app.${var.domain}/ready has not answered 200: no control plane serves."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.controlplane.id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  # No data is a health check that no longer reports, which tells as little as one failing.
  treat_missing_data = "breaching"
  alarm_actions      = [aws_sns_topic.controlplane_down.arn]
  ok_actions         = [aws_sns_topic.controlplane_down.arn]
  tags               = merge(local.tags, { "spin:role" = "alerts" })
}

# Over the group, the machines being the group's: the worst of them, so a machine an update
# started beside the old one tells as well. A group with no machine at all has no data, which is
# the control plane down too.
resource "aws_cloudwatch_metric_alarm" "controlplane_machine" {
  alarm_name          = "${local.iam_name}-controlplane-status-check"
  alarm_description   = "EC2's status checks of the control plane's machine fail."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.controlplane.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.security.arn]
  ok_actions          = [aws_sns_topic.security.arn]
  tags                = merge(local.tags, { "spin:role" = "alerts" })
}
