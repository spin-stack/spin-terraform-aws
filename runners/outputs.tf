output "autoscaling_group" {
  value = aws_autoscaling_group.runner.name
}

output "security_group_id" {
  value = aws_security_group.runner.id
}
