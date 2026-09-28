output "autoscaling_group" {
  description = "The runners' group, which the control plane sizes: empty until a workspace waits for a host."
  value       = aws_autoscaling_group.runner.name
}

output "security_group_id" {
  description = "The runners' security group: nothing in, everything out - a workspace's egress is filtered on the host by spin."
  value       = aws_security_group.runner.id
}
