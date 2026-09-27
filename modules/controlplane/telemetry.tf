# The installation's telemetry: Grafana Alloy on the control plane's machine is the one collector,
# the control plane, the proxy and every runner push OTLP to it inside the VPC, and it keeps what
# it is given in the stores beside it on that machine - Quickwit and VictoriaMetrics, over the
# logs bucket (logs_bucket.tf). Nothing leaves the installation, and no token for a backend is
# anywhere. Which traces and metrics are kept is the dashboard's (Admin -> Settings -> Telemetry).

variable "collector" {
  description = "The collector: how often metrics are pushed to it. Which Alloy it is, is the image's."
  type = object({
    metric_interval = optional(string, "60s")
  })
  default  = {}
  nullable = false
  validation {
    condition     = can(regex("^[0-9]+s$", var.collector.metric_interval))
    error_message = "collector.metric_interval is whole seconds, e.g. 60s."
  }
}

locals {
  # Where every process of the installation pushes.
  collector       = "${local.cp_host}:4317"
  metric_interval = var.collector.metric_interval
}

# The collector's port, to the processes that push to it: the proxy here, the runners in their
# module. Nothing else reaches it.
resource "aws_vpc_security_group_ingress_rule" "collector_from_proxy" {
  security_group_id            = aws_security_group.controlplane.id
  referenced_security_group_id = aws_security_group.proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  description                  = "telemetry from the proxy"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_collector" {
  security_group_id            = aws_security_group.proxy.id
  referenced_security_group_id = aws_security_group.controlplane.id
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  description                  = "the collector"
}
