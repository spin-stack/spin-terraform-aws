# The runners' groups are the control plane's: it makes one per host class, from the runners
# module's launch template, and none of them is in this state. So a destroy takes them away here,
# with the machines in them, after the control plane is gone - one still running would make them
# again - and before the subnets and the security groups they are in, which AWS will not delete
# with a machine in them. It runs the AWS CLI as whoever runs the destroy, which the README asks of
# them already.
resource "terraform_data" "runner_groups" {
  input = {
    region = local.region
    name   = local.name
    # Held here so the network goes after the groups, not before.
    subnets = aws_subnet.public[*].id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/sh", "-c"]
    environment = {
      AWS_REGION   = self.input.region
      INSTALLATION = self.input.name
    }
    command = <<-EOT
      set -eu
      groups() {
        aws autoscaling describe-auto-scaling-groups \
          --filters "Name=tag:spin:installation,Values=$INSTALLATION" \
          --query "AutoScalingGroups[?starts_with(AutoScalingGroupName, '$INSTALLATION-runners-')].AutoScalingGroupName" \
          --output text
      }
      for g in $(groups); do
        echo "taking away the runners' group $g and its machines"
        aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$g" --force-delete || true
      done
      while [ -n "$(groups)" ]; do sleep 10; done
    EOT
  }
}
