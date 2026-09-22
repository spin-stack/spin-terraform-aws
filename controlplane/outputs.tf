output "vpc_id" {
  description = "The VPC the runners go in."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "One public subnet per zone, for the runners' group."
  value       = aws_subnet.public[*].id
}

output "security_group_id" {
  description = "The control plane's group; the runners module opens 8080 on it to its own."
  value       = aws_security_group.controlplane.id
}

output "cosign" {
  description = "The cosign every machine checks the release with, and its pinned SHA-256: the runners' too."
  value       = var.cosign
}

output "url" {
  description = "The control plane as runners reach it, the address its certificate names."
  value       = local.url
}

output "token_parameter" {
  description = "The SSM parameter holding the pool's current registration token."
  value       = aws_ssm_parameter.token.name
}

output "token_parameter_arn" {
  value = aws_ssm_parameter.token.arn
}

output "ca_parameter" {
  description = "The SSM parameter holding the control plane's CA."
  value       = aws_ssm_parameter.ca.name
}

output "ca_parameter_arn" {
  value = aws_ssm_parameter.ca.arn
}

output "domain" {
  description = "The base domain; the runners resolve its relay, tunnel.app.<domain>, to proxy_private_ip."
  value       = var.domain
}

output "internal_zone_id" {
  description = "The private zone the components reach each other by, cp.<internal_zone> and proxy.<internal_zone>."
  value       = aws_route53_zone.internal.zone_id
}

output "proxy_private_ip" {
  description = "The proxy inside the VPC: where the runners' relay goes, without leaving it."
  value       = local.proxy_ip
}

output "collector" {
  description = "Where every process of the installation pushes its telemetry, host:port; empty ships nothing."
  value       = local.collector
}

output "metric_interval" {
  description = "How often a process pushes its metrics to the collector; empty is the binary's default."
  value       = local.metric_interval
}

output "grafana_token_parameter" {
  description = "Where the Grafana Cloud access policy token goes: aws ssm put-parameter --overwrite --type SecureString --name <this> --value <token>. Empty without grafana_cloud."
  value       = local.telemetry ? aws_ssm_parameter.grafana_token[0].name : ""
}

output "boundary_arn" {
  description = "The permissions boundary every role of the installation carries; the runners module puts it on the runners' role."
  value       = aws_iam_policy.boundary.arn
}

output "unpublished" {
  description = "What the two parameters hold until the control plane has written them."
  value       = local.unpublished
}

output "proxy_ip" {
  description = "The proxy's elastic IP, where app.<domain> and *.app.<domain> point: the one address of the installation the internet reaches."
  value       = aws_eip.proxy.public_ip
}

output "proxy_instance_id" {
  description = "For `aws ssm start-session --target`: the proxy has no SSH either."
  value       = aws_instance.proxy.id
}

output "bucket" {
  value = aws_s3_bucket.volumes.bucket
}

output "instance_id" {
  description = "For `aws ssm start-session --target`, which is how the machine is reached: it has no SSH."
  value       = aws_instance.controlplane.id
}
