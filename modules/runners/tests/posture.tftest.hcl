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
  controlplane = {
    name                       = "spin"
    vpc_id                     = "vpc-00000000000000000"
    subnet_ids                 = ["subnet-00000000000000000"]
    security_group_id          = "sg-00000000000000000"
    url                        = "https://10.42.0.10:8080"
    token_parameter            = "/spin/runner-registration-token"
    token_parameter_arn        = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-registration-token"
    ca_parameter               = "/spin/controlplane-ca"
    ca_parameter_arn           = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/controlplane-ca"
    unpublished                = "unpublished"
    boundary_arn               = "arn:aws:iam::123456789012:policy/spin-boundary"
    domain                     = "example.com"
    relay_dial                 = "proxy.spin.internal:443"
    collector                  = ""
    metric_interval            = ""
    fetch_release              = "release() { : the control plane module's; }"
    session_manager_policy_arn = "arn:aws:iam::123456789012:policy/spin-session-manager"
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
  # The relay by the proxy's private name, so it stays in the VPC and follows a replaced proxy.
  assert {
    condition     = strcontains(base64decode(aws_launch_template.runner.user_data), "--relay-dial 'proxy.spin.internal:443'") && !strcontains(base64decode(aws_launch_template.runner.user_data), "/etc/hosts")
    error_message = "a runner reaches the relay by the proxy's public address, or by an address a replaced proxy does not have"
  }
  assert {
    condition     = aws_launch_template.runner.cpu_options[0].nested_virtualization == "enabled"
    error_message = "a runner is started without KVM"
  }
  assert {
    condition     = alltrue([for b in aws_launch_template.runner.block_device_mappings : b.ebs[0].encrypted == "true"])
    error_message = "a runner's disk is not encrypted"
  }
  # Its installer is the release its control plane serves, asked of it - never a version this
  # module was given, which an update of the control plane may not have reached yet - and it is
  # fetched with the control plane module's own checked download. The token is no argument.
  assert {
    condition = alltrue([for want in [
      "release() { : the control plane module's; }",
      "-H @/etc/spin-bootstrap/token.header \\\n    'https://10.42.0.10:8080/platform-images/runner'",
      "tolower($1) == \"x-spin-runner-version\"",
      "release \"$version\" spin-install-linux-amd64",
    ] : strcontains(base64decode(aws_launch_template.runner.user_data), want)]) && !strcontains(base64decode(aws_launch_template.runner.user_data), "Bearer $token\" ")
    error_message = "a runner installs a release other than its control plane's, or fetches it unchecked"
  }
}

run "a_runner_pushes_to_the_collector_where_there_is_one" {
  command = plan
  variables {
    controlplane = {
      name                       = "spin"
      vpc_id                     = "vpc-00000000000000000"
      subnet_ids                 = ["subnet-00000000000000000"]
      security_group_id          = "sg-00000000000000000"
      url                        = "https://cp.spin.internal:8080"
      token_parameter            = "/spin/runner-registration-token"
      token_parameter_arn        = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/runner-registration-token"
      ca_parameter               = "/spin/controlplane-ca"
      ca_parameter_arn           = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/controlplane-ca"
      unpublished                = "unpublished"
      boundary_arn               = "arn:aws:iam::123456789012:policy/spin-boundary"
      domain                     = "example.com"
      relay_dial                 = "proxy.spin.internal:443"
      collector                  = "cp.spin.internal:4317"
      metric_interval            = "60s"
      fetch_release              = "release() { : the control plane module's; }"
      session_manager_policy_arn = "arn:aws:iam::123456789012:policy/spin-session-manager"
    }
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.collector_from_runners[0].from_port == 4317 && aws_vpc_security_group_ingress_rule.collector_from_runners[0].security_group_id == "sg-00000000000000000"
    error_message = "the collector's port is not opened to the runners"
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.runner.user_data), "--otel-collector 'cp.spin.internal:4317' --otel-metric-interval '60s'")
    error_message = "a runner is not pointed at the collector"
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
