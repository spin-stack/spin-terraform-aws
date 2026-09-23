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
  target = data.aws_ami.ubuntu
  values = { id = "ami-0123456789abcdef0" }
}

variables {
  controlplane = {
    name                        = "spin"
    vpc_id                      = "vpc-00000000000000000"
    subnet_ids                  = ["subnet-00000000000000000"]
    security_group_id           = "sg-00000000000000000"
    runner_config_parameter_arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-config"
    runner_user_data            = "#!/bin/sh\n# the control plane module's\nexec /usr/local/bin/spin-boot runner --config 'ssm:///spin/runner-config?region=us-east-2'\n"
    boot_log_policy_arn         = "arn:aws:iam::123456789012:policy/spin-boot-log"
    boundary_arn                = "arn:aws:iam::123456789012:policy/spin-boundary"
    collector                   = ""
    session_manager_policy_arn  = "arn:aws:iam::123456789012:policy/spin-session-manager"
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
    condition     = length(aws_vpc_security_group_ingress_rule.collector_from_runners) == 0
    error_message = "the collector's port is opened on an installation with no collector"
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
  # What a runner's machine runs is the control plane module's, as it is: spin-boot over the
  # runners' document, which says everything else.
  assert {
    condition     = base64decode(aws_launch_template.runner.user_data) == var.controlplane.runner_user_data
    error_message = "a runner's machine runs something other than spin-boot over its document"
  }
}

run "a_runner_pushes_to_the_collector_where_there_is_one" {
  command = plan
  variables {
    controlplane = {
      name                        = "spin"
      vpc_id                      = "vpc-00000000000000000"
      subnet_ids                  = ["subnet-00000000000000000"]
      security_group_id           = "sg-00000000000000000"
      runner_config_parameter_arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-config"
      runner_user_data            = "#!/bin/sh\n"
      boot_log_policy_arn         = "arn:aws:iam::123456789012:policy/spin-boot-log"
      boundary_arn                = "arn:aws:iam::123456789012:policy/spin-boundary"
      collector                   = "cp.spin.internal:4317"
      session_manager_policy_arn  = "arn:aws:iam::123456789012:policy/spin-session-manager"
    }
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.collector_from_runners[0].from_port == 4317 && aws_vpc_security_group_ingress_rule.collector_from_runners[0].security_group_id == "sg-00000000000000000"
    error_message = "the collector's port is not opened to the runners"
  }
}

# A runner joins by who it is, so its role reads its document and nothing else: no token, and no
# credential to the bucket, which the control plane mints an hour at a time.
run "a_runners_role_reads_its_document" {
  command = plan

  assert {
    condition     = aws_iam_role.runner.permissions_boundary == "arn:aws:iam::123456789012:policy/spin-boundary"
    error_message = "the runners' role carries no boundary"
  }
  assert {
    condition = length(data.aws_iam_policy_document.runner.statement) == 1 && alltrue([for s in data.aws_iam_policy_document.runner.statement :
    s.actions == toset(["ssm:GetParameter"]) && s.resources == toset(["arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-config"])])
    error_message = "the runners' role may do more than read its document"
  }
  # The role's name is the one the installation's configuration names as a host's
  # (modules/controlplane, host_join): a runner of another role joins nothing.
  assert {
    condition     = aws_iam_role.runner.name == "spin-runner"
    error_message = "the runners' role is not the one the installation lets join"
  }
  # Session Manager by the control plane module's own policy, which is a session and no more:
  # the managed one reads every parameter in the account, the encryption key among them.
  assert {
    condition     = aws_iam_role_policy_attachment.runner_ssm[0].policy_arn == "arn:aws:iam::123456789012:policy/spin-session-manager"
    error_message = "a runner is given more of SSM than a session"
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
