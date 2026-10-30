output "launch_template" {
  description = "The runners' launch template, which every host class's group the control plane makes starts its machines from; its default version is the release's."
  value       = aws_launch_template.runner.name
}

output "security_group_id" {
  description = "The runners' security group: nothing in, everything out - a workspace's egress is filtered on the host by spin."
  value       = aws_security_group.runner.id
}
