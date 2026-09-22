# The installation's telemetry, to Grafana Cloud, where one is given: Grafana Alloy on the
# control plane's machine is the one collector, the control plane, the proxy and every runner
# push OTLP to it inside the VPC, and only it holds the token and reaches Grafana Cloud. Which
# traces and metrics leave is the dashboard's (Admin -> Settings -> Telemetry), read by Alloy
# from the control plane; which logs, the least severity below.

variable "grafana_cloud" {
  description = <<-EOT
    Ship the installation's telemetry to a Grafana Cloud stack; null ships nothing and installs
    no collector. otlp_endpoint and instance_id are the stack's OTLP gateway and its user, from
    the stack's OpenTelemetry page. The token is not here: write an access policy token with
    metrics:write, logs:write and traces:write alone into the SSM parameter this creates
    (grafana_token_parameter), and it never reaches Terraform's state or a machine's user data.
  EOT
  type = object({
    otlp_endpoint   = string
    instance_id     = string
    log_severity    = optional(string, "WARN")
    metric_interval = optional(string, "60s")
    alloy_version   = optional(string, "1.19.2")
    # The SHA-256 of that version's alloy-<v>-1.amd64.deb, from the release's SHA256SUMS: the
    # package is checked against it before it is installed.
    alloy_sha256 = optional(string, "9872732d43c6d14996e1ad5a075086a93381ea6375c8c756820da68b85422eea")
  })
  default = null
  validation {
    condition     = var.grafana_cloud == null || contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], try(var.grafana_cloud.log_severity, ""))
    error_message = "grafana_cloud.log_severity is one of TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
  validation {
    condition     = var.grafana_cloud == null || can(regex("^[0-9]+s$", try(var.grafana_cloud.metric_interval, "")))
    error_message = "grafana_cloud.metric_interval is whole seconds, e.g. 60s."
  }
  validation {
    condition     = var.grafana_cloud == null || can(regex("^[0-9a-f]{64}$", try(var.grafana_cloud.alloy_sha256, "")))
    error_message = "grafana_cloud.alloy_sha256 is the package's SHA-256, 64 hex digits."
  }
}

locals {
  telemetry = var.grafana_cloud != null
  # Where every process of the installation pushes; empty ships nothing.
  collector               = local.telemetry ? "${local.private_ip}:4317" : ""
  metric_interval         = local.telemetry ? var.grafana_cloud.metric_interval : ""
  token_parameter_grafana = "/${var.name}/grafana-cloud-token"
}

resource "aws_ssm_parameter" "grafana_token" {
  count       = local.telemetry ? 1 : 0
  name        = local.token_parameter_grafana
  description = "The Grafana Cloud access policy token ${var.name}'s collector ships with; written by the operator"
  type        = "SecureString"
  value       = local.unpublished
  tags        = local.tags
  lifecycle {
    ignore_changes = [value]
  }
}

# The collector's port, to the processes that push to it: the proxy here, the runners in their
# module. Nothing else reaches it.
resource "aws_vpc_security_group_ingress_rule" "collector_from_proxy" {
  count                        = local.telemetry ? 1 : 0
  security_group_id            = aws_security_group.controlplane.id
  referenced_security_group_id = aws_security_group.proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  description                  = "the proxy's telemetry"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_collector" {
  count                        = local.telemetry ? 1 : 0
  security_group_id            = aws_security_group.proxy.id
  referenced_security_group_id = aws_security_group.controlplane.id
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  description                  = "the collector"
}
