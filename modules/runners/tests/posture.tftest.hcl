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

# Every type 48 vCPUs, and an account with room; the quota's runs give it a new account's 32.
override_data {
  target = data.aws_ec2_instance_type.runner
  values = { default_vcpus = 48 }
}

override_data {
  target = data.aws_servicequotas_service_quota.runners
  values = { value = 1000, quota_name = "All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests" }
}

variables {
  controlplane = {
    name                        = "spin"
    iam_name                    = "spin-us-east-2"
    vpc_id                      = "vpc-00000000000000000"
    subnet_ids                  = ["subnet-00000000000000000"]
    security_group_id           = "sg-00000000000000000"
    runner_config_parameter_arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-config"
    runner_user_data            = "{\"systemd.credentials\":[{\"name\":\"spin.role\",\"text\":\"runner\"},{\"name\":\"spin.config\",\"text\":\"ssm:///spin/runner-config?region=us-east-2\"}]}"
    images = {
      "control-plane" = { id = "ami-0aaaaaaaaaaaaaaaa", root_device = "/dev/sda1" }
      runner          = { id = "ami-0123456789abcdef0", root_device = "/dev/xvda" }
      proxy           = { id = "ami-0bbbbbbbbbbbbbbbb", root_device = "/dev/sda1" }
    }
    boot_log_policy_arn = "arn:aws:iam::123456789012:policy/spin-boot-log"
    standard_vcpus      = 8
    boundary_arn        = "arn:aws:iam::123456789012:policy/spin-boundary"
  }
}

# The template's version, which a plan knows only once it is applied.
override_resource {
  target = aws_launch_template.runner
  values = { id = "lt-00000000000000000", latest_version = 7 }
}

run "a_runner_is_reached_by_nothing" {
  command = plan

  # The one ingress rule this module writes is on the control plane's group, for 8080.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.controlplane_from_runners.security_group_id == "sg-00000000000000000" && aws_vpc_security_group_ingress_rule.controlplane_from_runners.from_port == 8080 && aws_vpc_security_group_ingress_rule.controlplane_from_runners.cidr_ipv4 == null
    error_message = "the runners module opens something other than the control plane's 8080 to the runners"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.collector_from_runners.from_port == 4317 && aws_vpc_security_group_ingress_rule.collector_from_runners.security_group_id == "sg-00000000000000000" && aws_vpc_security_group_ingress_rule.collector_from_runners.cidr_ipv4 == null
    error_message = "the collector's port is not opened to the runners alone"
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
  # What a runner's machine is told is the control plane module's, as it is: its role and the
  # runners' document, which says everything else.
  assert {
    condition     = base64decode(aws_launch_template.runner.user_data) == var.controlplane.runner_user_data
    error_message = "a runner's machine is told something other than its role and its document"
  }
  # And it boots the runner's image of the installation's release - not the control plane's nor the
  # proxy's, each signed by another key - on that image's root device. The group names the template's version by number: a new image is a change to the group
  # the plan shows, where "$Latest" is the same string before and after.
  assert {
    condition = (
      aws_launch_template.runner.image_id == "ami-0123456789abcdef0" &&
      anytrue([for b in aws_launch_template.runner.block_device_mappings : b.device_name == "/dev/xvda"]) &&
      aws_autoscaling_group.runner.mixed_instances_policy[0].launch_template[0].launch_template_specification[0].version == "7"
    )
    error_message = "a runner boots another image than the installation's runner's, or the group cannot tell a new one"
  }
  # A release moves no workspace unless the installation says so: nothing refreshes the group, and
  # the next host it starts once the control plane has emptied it boots the new image.
  assert {
    condition     = length(aws_autoscaling_group.runner.instance_refresh) == 0
    error_message = "a new release replaces the runners under their workspaces"
  }
}

# Rolling, for a fleet that never empties: the new release replaces the hosts at once, one at a
# time and the new one first, each old one's workspaces leaving by the drain.
run "a_rolling_fleet_is_replaced_at_once" {
  command = plan
  variables {
    rollout = "rolling"
  }
  assert {
    condition = (
      aws_autoscaling_group.runner.instance_refresh[0].strategy == "Rolling" &&
      aws_autoscaling_group.runner.instance_refresh[0].preferences[0].min_healthy_percentage == 100 &&
      aws_autoscaling_group.runner.instance_refresh[0].preferences[0].max_healthy_percentage == 200
    )
    error_message = "a rolling fleet keeps its old release, or loses a host before its replacement is up"
  }
}

run "a_rollout_that_is_neither_is_refused" {
  command = plan
  variables {
    rollout = "nightly"
  }
  expect_failures = [var.rollout]
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
    condition     = aws_iam_role.runner.name == "spin-us-east-2-runner" && aws_iam_instance_profile.runner.name == "spin-us-east-2-runner"
    error_message = "the runners' role is not the one the installation lets join"
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

# A quota lower than max_hosts of the largest type is asked of AWS, for exactly that; spot and
# on-demand are two quotas, and on-demand runners share theirs with the control plane and the proxy.
run "the_quota_the_runners_need_is_asked_for" {
  command = plan
  variables {
    max_hosts = 2
  }
  assert {
    condition = (
      aws_servicequotas_service_quota.runners[0].quota_code == "L-34B43A08" &&
      aws_servicequotas_service_quota.runners[0].value == 96
    )
    error_message = "the spot quota two runners of 48 vCPUs need is not asked for"
  }
  expect_failures = [check.room_for_runners]
  override_data {
    target = data.aws_servicequotas_service_quota.runners
    values = { value = 32, quota_name = "a new account's" }
  }
}

run "on_demand_runners_share_their_quota" {
  command = plan
  variables {
    spot = false
  }
  assert {
    condition = (
      aws_servicequotas_service_quota.runners[0].quota_code == "L-1216C47A" &&
      aws_servicequotas_service_quota.runners[0].value == 56
    )
    error_message = "the on-demand quota does not count the control plane's and the proxy's machines"
  }
  expect_failures = [check.room_for_runners]
  override_data {
    target = data.aws_servicequotas_service_quota.runners
    values = { value = 32, quota_name = "a new account's" }
  }
}

run "no_request_when_asked_not_to" {
  command = plan
  variables {
    request_quota = false
  }
  assert {
    condition     = length(aws_servicequotas_service_quota.runners) == 0
    error_message = "a quota was requested by an installation that said not to"
  }
  expect_failures = [check.room_for_runners]
  override_data {
    target = data.aws_servicequotas_service_quota.runners
    values = { value = 32, quota_name = "a new account's" }
  }
}
