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
