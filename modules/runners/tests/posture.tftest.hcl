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

# An account with room; the quota's runs give it a new account's 32.
override_data {
  target = data.aws_servicequotas_service_quota.runners
  values = { value = 1000, quota_name = "All Standard (A, C, D, H, I, M, R, T, Z) Spot Instance Requests" }
}

variables {
  controlplane = {
    name                = "spin"
    iam_name            = "spin-us-east-2"
    vpc_id              = "vpc-00000000000000000"
    subnet_ids          = ["subnet-00000000000000000"]
    security_group_id   = "sg-00000000000000000"
    runner_document_arn = "arn:aws:s3:::spin-docs-123456789012-us-east-2/runner.yaml"
    runner_user_data    = "{\"systemd.credentials\":[{\"name\":\"spin.role\",\"text\":\"runner\"},{\"name\":\"spin.config\",\"text\":\"s3://spin-docs-123456789012-us-east-2/runner.yaml?region=us-east-2\"}]}"
    images = {
      "control-plane" = { id = "ami-0aaaaaaaaaaaaaaaa", root_device = "/dev/sda1" }
      runner          = { id = "ami-0123456789abcdef0", root_device = "/dev/xvda" }
      proxy           = { id = "ami-0bbbbbbbbbbbbbbbb", root_device = "/dev/sda1" }
    }
    boot_log_policy_arn = "arn:aws:iam::123456789012:policy/spin-boot-log"
    standard_vcpus      = 8
    boundary_arn        = "arn:aws:iam::123456789012:policy/spin-boundary"
    runner_groups       = "the-runner-groups"
  }
  runners = {
    launch_template       = "spin-runner"
    controlplane_role     = "spin-us-east-2-controlplane"
    vcpus_max             = 48
    max_hosts             = 1
    spot                  = true
    data_volume_gb        = 0
    nested_virtualization = true
  }
}

# The runners' role's ARN, and the template's id and version, which a plan knows only once
# they are applied.
override_resource {
  target = aws_iam_role.runner
  values = { arn = "arn:aws:iam::123456789012:role/spin-us-east-2-runner" }
}
override_resource {
  target = aws_launch_template.runner
  values = { id = "lt-00000000000000000", latest_version = 7, arn = "arn:aws:ec2:us-east-2:123456789012:launch-template/lt-00000000000000000" }
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
  # What a runner costs is read off the bill by its role: the machine and its disks alike.
  assert {
    condition     = alltrue([for t in aws_launch_template.runner.tag_specifications : t.tags["spin:role"] == "runner"])
    error_message = "a runner's machine or disk is not tagged as a runner's, and its cost is no role's"
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
  # proxy's, each signed by another key - on that image's root device. The template is the one
  # the control plane makes its groups from, by name, and a release is its default version.
  assert {
    condition = (
      aws_launch_template.runner.image_id == "ami-0123456789abcdef0" &&
      anytrue([for b in aws_launch_template.runner.block_device_mappings : b.device_name == "/dev/xvda"]) &&
      aws_launch_template.runner.name == "spin-runner" && aws_launch_template.runner.update_default_version
    )
    error_message = "a runner boots another image than the installation's runner's, or the groups would not start a new one"
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
    s.actions == toset(["s3:GetObject"]) && s.resources == toset(["arn:aws:s3:::spin-docs-123456789012-us-east-2/runner.yaml"])])
    error_message = "the runners' role may do more than read its document"
  }
  # The role's name is the one the installation's configuration names as a host's
  # (modules/controlplane, host_join): a runner of another role joins nothing.
  assert {
    condition     = aws_iam_role.runner.name == "spin-us-east-2-runner" && aws_iam_instance_profile.runner.name == "spin-us-east-2-runner"
    error_message = "the runners' role is not the one the installation lets join"
  }
}

# The groups are the control plane's to make, hold and size - this installation's alone, by name
# and by tag - and what making one asks of it is to start this template and pass its role: never
# another template, which is another image, nor another role.
run "the_groups_are_the_control_planes_and_start_only_this_template" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.controlplane_fleet.role == "spin-us-east-2-controlplane"
    error_message = "the runners' groups are granted to another role than the control plane's"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane_fleet.statement :
      alltrue([for r in s.resources : r == "*" || endswith(r, "autoScalingGroupName/spin-runners-*") || r == aws_iam_role.runner.arn])
    ])
    error_message = "the control plane may touch a group that is not one of this installation's runners'"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane_fleet.statement :
      anytrue([for c in s.condition : c.variable == "aws:RequestTag/spin:installation" || c.variable == "aws:ResourceTag/spin:installation"]) && alltrue([for c in s.condition : contains(c.values, "spin")])
      if anytrue([for a in s.actions : startswith(a, "autoscaling:") && !startswith(a, "autoscaling:Describe")])
    ])
    error_message = "a group may be made or changed without being this installation's"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane_fleet.statement :
      anytrue([for c in s.condition : c.variable == "ec2:LaunchTemplate" && contains(c.values, "arn:aws:ec2:us-east-2:123456789012:launch-template/lt-00000000000000000") && length(c.values) == 1])
      if contains(s.actions, "ec2:RunInstances")
    ])
    error_message = "the control plane may start a machine from another template than the runners'"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane_fleet.statement :
      s.resources == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-runner"]) if contains(s.actions, "iam:PassRole")
    ])
    error_message = "the control plane may pass another role than the runners'"
  }
}

run "the_quota_is_sized_by_the_largest_runner" {
  command = plan
  variables {
    runners = { launch_template = "spin-runner", controlplane_role = "spin-us-east-2-controlplane", vcpus_max = 64, max_hosts = 2, spot = true, data_volume_gb = 0, nested_virtualization = true }
  }
  assert {
    condition     = aws_servicequotas_service_quota.runners[0].value == 128
    error_message = "the quota is not sized for two runners of the vCPUs' top"
  }
  expect_failures = [check.room_for_runners]
  override_data {
    target = data.aws_servicequotas_service_quota.runners
    values = { value = 32, quota_name = "a new account's" }
  }
}

# A quota lower than max_hosts of the largest type is asked of AWS, for exactly that; spot and
# on-demand are two quotas, and on-demand runners share theirs with the control plane and the proxy.
run "the_quota_the_runners_need_is_asked_for" {
  command = plan
  variables {
    runners = { launch_template = "spin-runner", controlplane_role = "spin-us-east-2-controlplane", vcpus_max = 48, max_hosts = 2, spot = true, data_volume_gb = 0, nested_virtualization = true }
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
    runners = { launch_template = "spin-runner", controlplane_role = "spin-us-east-2-controlplane", vcpus_max = 48, max_hosts = 1, spot = false, data_volume_gb = 0, nested_virtualization = true }
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
