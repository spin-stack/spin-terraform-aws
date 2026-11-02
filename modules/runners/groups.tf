# The runners' groups are the control plane's: it makes one per host class, from this module's
# launch template, and none of them is in this state. So a destroy takes them away here, with the
# machines in them. A destroy takes what depends on a thing before the thing, so this depends on
# what their machines sit in - the security group, the template, the subnets - which AWS will not
# delete with a machine in them, and the control plane's group depends on this, since one still
# running would make them again. It runs the AWS CLI as whoever runs the destroy, which the README
# asks of them already.

data "aws_region" "current" {}

resource "terraform_data" "runner_groups" {
  input = {
    region          = data.aws_region.current.region
    name            = local.name
    security_group  = aws_security_group.runner.id
    launch_template = aws_launch_template.runner.id
    subnets         = var.controlplane.subnet_ids
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
