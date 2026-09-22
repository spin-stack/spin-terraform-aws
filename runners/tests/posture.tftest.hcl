# What this module promises about the runners, held against its plan; see the control plane
# module's tests for how nothing here reaches an account.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2", name = "us-east-2" }
}

override_data {
  target = data.aws_ami.ubuntu
  values = { id = "ami-0123456789abcdef0" }
}

variables {
  spin_version = "v20260921.02"
  controlplane = {
    vpc_id              = "vpc-00000000000000000"
    subnet_ids          = ["subnet-00000000000000000"]
    security_group_id   = "sg-00000000000000000"
    url                 = "https://10.42.0.10:8080"
    token_parameter     = "/spin/runner-registration-token"
    token_parameter_arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-registration-token"
    ca_parameter        = "/spin/controlplane-ca"
    ca_parameter_arn    = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/controlplane-ca"
    unpublished         = "unpublished"
    boundary_arn        = "arn:aws:iam::123456789012:policy/spin-boundary"
  }
}

run "a_runner_is_reached_by_nothing" {
  command = plan

  # The one ingress rule this module writes is on the control plane's group, for 8080.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.controlplane_from_runners.security_group_id == "sg-00000000000000000" && aws_vpc_security_group_ingress_rule.controlplane_from_runners.from_port == 8080 && aws_vpc_security_group_ingress_rule.controlplane_from_runners.cidr_ipv4 == null
    error_message = "the runners module opens something other than the control plane's 8080 to the runners"
  }
  assert {
    condition     = aws_launch_template.runner.metadata_options[0].http_tokens == "required" && aws_launch_template.runner.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "a runner answers IMDSv1, or its guests' side of the host can reach the role"
  }
  assert {
    condition     = aws_launch_template.runner.cpu_options[0].nested_virtualization == "enabled"
    error_message = "a runner is started without KVM"
  }
  assert {
    condition     = alltrue([for b in aws_launch_template.runner.block_device_mappings : b.ebs[0].encrypted == "true"])
    error_message = "a runner's disk is not encrypted"
  }
}

run "a_runners_role_reads_two_parameters" {
  command = plan

  assert {
    condition     = aws_iam_role.runner.permissions_boundary == "arn:aws:iam::123456789012:policy/spin-boundary"
    error_message = "the runners' role carries no boundary"
  }
  assert {
    condition = length(data.aws_iam_policy_document.runner.statement) == 1 && alltrue([for s in data.aws_iam_policy_document.runner.statement :
    s.actions == toset(["ssm:GetParameter"]) && length(s.resources) == 2])
    error_message = "the runners' role may do more than read the token and the CA"
  }
}

run "the_group_is_the_control_planes_to_size" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.runner.name == "spin-runners" && aws_autoscaling_group.runner.min_size == 0
    error_message = "the group is not the one the control plane's role may resize, or cannot be emptied"
  }
  assert {
    condition = anytrue([for h in aws_autoscaling_group.runner.initial_lifecycle_hook :
    h.lifecycle_transition == "autoscaling:EC2_INSTANCE_TERMINATING" && h.default_result == "CONTINUE"])
    error_message = "a host the group takes away is not held while it drains"
  }
}
