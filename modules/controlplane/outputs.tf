output "name" {
  description = "The installation's name, which the runners' group, role and SSM path are named for."
  value       = var.name
}

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

output "session_manager_policy_arn" {
  description = "Session Manager into a machine, and nothing else of SSM: what the runners' role is given in place of AmazonSSMManagedInstanceCore, which reads every parameter."
  value       = aws_iam_policy.session_manager.arn
}

output "fetch_release" {
  description = "The shell function every machine of the installation fetches a release file with, `release <version> <file>`: cosign by its pinned SHA-256, and the file verified against the release workflow at that version's tag."
  value       = local.fetch_release
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
  description = "The base domain; the runners' relay is tunnel.app.<domain>, dialled at relay_dial."
  value       = var.domain
}

output "internal_zone_id" {
  description = "The private zone the components reach each other by, cp.<internal_zone> and proxy.<internal_zone>."
  value       = aws_route53_zone.internal.zone_id
}

output "relay_dial" {
  description = "Where a runner dials the relay, host:port: the proxy inside the VPC, by the name the proxy of the moment points at itself."
  value       = "${local.proxy_host}:443"
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

output "proxy_group" {
  description = "The proxy's group of one. Its machine, for `aws ssm start-session --target` (it has no SSH): aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <this> --query 'AutoScalingGroups[0].Instances[0].InstanceId'."
  value       = aws_autoscaling_group.proxy.name
}

output "bucket" {
  value = aws_s3_bucket.volumes.bucket
}

output "controlplane_group" {
  description = "The control plane's group of one. `aws autoscaling start-instance-refresh --auto-scaling-group-name <this>` replaces its machine beside itself; its machine is reached with `aws ssm start-session`, as the proxy's is."
  value       = aws_autoscaling_group.controlplane.name
}
