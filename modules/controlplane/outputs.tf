output "name" {
  description = "The installation's name, claimed in its region (claim.tf), which the runners' group and security group are named for."
  value       = local.name
}

output "iam_name" {
  description = "What the installation's IAM names begin with: its name and its region, since IAM is the account's and two regions may each have an installation of one name. The runners' role and instance profile are named for it."
  value       = local.iam_name
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
  description = "A runner's user data: its role and the runners' document, as the systemd credentials Spin OS's spin-boot takes."
  value       = local.user_data["runner"]
}

output "images" {
  description = "The Spin OS images of the installation's release, by role - the control plane's, the runners' and the proxy's: each one's id and root device. The runners module boots the runner's."
  value       = { for role in local.roles : role => { id = local.image[role], root_device = local.root_device[role] } }
}

output "boot_log_group" {
  description = "The CloudWatch log group every machine's boot writes to, a stream per <role>/<step>/<instance-id>: a role's machines are one stream prefix."
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

output "name_servers" {
  description = "The domain's public zone's nameservers, which its registrar points at."
  value       = aws_route53_zone.public.name_servers
}

output "domain" {
  description = "The base domain; the runners' relay is tunnel.app.<domain>, dialled at relay_dial."
  value       = var.domain
}

output "public_zone_id" {
  description = "The domain's public zone, where modules/identity-issuer puts id.<domain>."
  value       = aws_route53_zone.public.zone_id
}

output "identity_key_arn" {
  description = "The KMS key the control plane signs its workspaces' identity tokens with."
  value       = aws_kms_key.identity.arn
}

output "identity_documents" {
  description = "The commands that write the identity issuer's documents - discovery, key set, allowed signers and SPIFFE bundle - for modules/identity-issuer to publish: the X.509 CA the control plane made and keeps in its bucket, then the documents from it and the key's public half. Run them with credentials that may read both, and commit what they write."
  value       = "aws s3 cp s3://${aws_s3_bucket.volumes.bucket}/identity/x509-ca.der <dir>/x509-ca.der && spin-controlplane identity documents --kms-key ${aws_kms_key.identity.arn} --domain ${var.domain} --x509-ca <dir>/x509-ca.der --out <dir>"
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
  description = "Where every process of the installation pushes its telemetry, host:port. Where the collector sends it is set in the dashboard."
  value       = local.collector
}

output "boundary_arn" {
  description = "The permissions boundary every role of the installation carries; the runners module puts it on the runners' role."
  value       = aws_iam_policy.boundary.arn
}

output "proxy_ip" {
  description = "The proxy's elastic IP, where app.<domain>, tunnel.app.<domain> and *.ws.<domain> point: the one address of the installation the internet reaches."
  value       = aws_eip.proxy.public_ip
}

output "proxy_group" {
  description = "The proxy's group of one. Its machine, for `aws ssm start-session --target` (it has no SSH): aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <this> --query 'AutoScalingGroups[0].Instances[0].InstanceId'."
  value       = aws_autoscaling_group.proxy.name
}

output "bucket" {
  description = "The volumes' bucket: every workspace's disk, versioned under Object Lock, reached only through the VPC's endpoint."
  value       = aws_s3_bucket.volumes.bucket
}

output "database_bucket" {
  description = "The database's archive: the base backups and WAL the control plane ships as it writes, and restores from when its machine is replaced. Its role alone reaches it."
  value       = aws_s3_bucket.database.bucket
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
