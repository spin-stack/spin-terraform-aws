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

output "url" {
  description = "The control plane as runners reach it, the address its certificate names."
  value       = local.url
}

output "ca_cert" {
  description = "The installation's CA certificate, which every component trusts the control plane by."
  value       = tls_self_signed_cert.ca.cert_pem
}

output "runner_config_parameter_arn" {
  description = "The runners' document, which the runners' role reads and nothing else of SSM."
  value       = aws_ssm_parameter.runner_config.arn
}

output "runner_user_data" {
  description = "What a runner's machine runs at its first boot: spin-boot, by its digest, over the runners' document."
  value       = local.user_data["runner"]
}

output "boot_log_group" {
  description = "The CloudWatch log group every machine's boot writes to, a stream per instance."
  value       = aws_cloudwatch_log_group.boot.name
}

output "boot_log_policy_arn" {
  description = "Writing a machine's boot to that group, and nothing else: the runners module attaches it to the runners' role."
  value       = aws_iam_policy.boot_log.arn
}

output "standard_vcpus" {
  description = "The on-demand standard vCPUs the control plane's and the proxy's machines take at most: two of each while an update replaces one. The runners module counts them against the quota on-demand runners share."
  value       = 2 * (data.aws_ec2_instance_type.controlplane.default_vcpus + data.aws_ec2_instance_type.proxy.default_vcpus)
}

output "writes_public_dns" {
  description = "Whether this module writes app.<domain> and *.app.<domain>, or they are the operator's to point at proxy_ip."
  value       = var.route53_zone_id != ""
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
  value       = local.runner_document.relay_dial
}

output "collector" {
  description = "Where every process of the installation pushes its telemetry, host:port; empty ships nothing."
  value       = local.collector
}

output "grafana_token_parameter" {
  description = "Where the Grafana Cloud access policy token goes: aws ssm put-parameter --overwrite --type SecureString --name <this> --value <token>. Empty without grafana_cloud."
  value       = local.telemetry ? aws_ssm_parameter.grafana_token[0].name : ""
}

output "boundary_arn" {
  description = "The permissions boundary every role of the installation carries; the runners module puts it on the runners' role."
  value       = aws_iam_policy.boundary.arn
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

output "admin_email" {
  description = "Who the first administrator signs in as."
  value       = local.admin_email
}

output "admin_password_parameter" {
  description = "The SSM SecureString holding the first administrator's one-time password: aws ssm get-parameter --with-decryption --name <this>. The first sign-in asks for a new one."
  value       = aws_ssm_parameter.admin_password.name
}

output "region" {
  description = "The region everything here is in, read from the provider rather than asked for."
  value       = local.region
}

output "runner_idle_minutes" {
  description = "How long the fleet is idle before the runners' group is emptied, which is why a first workspace waits for a machine's boot."
  value       = var.runner_idle_minutes
}
