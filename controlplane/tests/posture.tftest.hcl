# What this module promises about who reaches what, held against its plan. Nothing is applied
# and no account is asked: the provider plans with credentials it never checks, and what it
# would read from the account is given here.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2", name = "us-east-2" }
}

override_data {
  target = data.aws_availability_zones.available
  values = { names = ["us-east-2a", "us-east-2b", "us-east-2c"] }
}

override_data {
  target = data.aws_ami.ubuntu
  values = { id = "ami-0123456789abcdef0" }
}

# Known at plan, so what carries it can be asserted on.
override_resource {
  target = aws_iam_policy.boundary
  values = { arn = "arn:aws:iam::123456789012:policy/spin-boundary" }
}

variables {
  spin_version = "v20260921.02"
  domain       = "example.com"
}

run "the_internet_reaches_the_proxy_alone" {
  command = plan

  # The control plane's one ingress rule is from another group, never from an address range.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.controlplane_from_proxy.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.controlplane_from_proxy.from_port == 8080
    error_message = "the control plane takes something from an address range, or on a port other than 8080"
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.controlplane : contains([80, 443], r.from_port) && r.ip_protocol == "tcp"])
    error_message = "the control plane reaches out on something other than 80 and 443"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.proxy_http.from_port == 80 && aws_vpc_security_group_ingress_rule.proxy_http.to_port == 80
    error_message = "the proxy's open rule is not the ACME challenge's port alone"
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.proxy_https : r.from_port == 443 && r.to_port == 443])
    error_message = "the users' rule on the proxy opens more than 443"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.proxy_https_vpc.cidr_ipv4 == var.vpc_cidr
    error_message = "the runners' relay rule is wider than the VPC"
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.proxy_web : contains([80, 443], r.from_port)]) && aws_vpc_security_group_egress_rule.proxy_to_controlplane.from_port == 8080
    error_message = "the proxy reaches out on something other than the control plane's 8080 and the web"
  }
}

run "a_list_of_networks_closes_the_proxy_to_everyone_else" {
  command = plan
  variables {
    proxy_allowed_cidrs = ["203.0.113.0/24", "198.51.100.0/24"]
  }
  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.proxy_https : r.cidr_ipv4]) == toset(["203.0.113.0/24", "198.51.100.0/24"])
    error_message = "the proxy's 443 is open to more than the networks listed"
  }
}

run "the_machines" {
  command = plan

  assert {
    condition     = aws_instance.controlplane.metadata_options[0].http_tokens == "required" && aws_instance.proxy.metadata_options[0].http_tokens == "required"
    error_message = "a machine answers IMDSv1"
  }
  assert {
    condition     = aws_instance.proxy.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "the proxy's container can reach the instance's role"
  }
  assert {
    condition     = aws_instance.controlplane.root_block_device[0].encrypted && aws_instance.proxy.root_block_device[0].encrypted && aws_ebs_volume.data.encrypted
    error_message = "a disk is not encrypted"
  }
  assert {
    condition     = aws_instance.proxy.private_ip != aws_instance.controlplane.private_ip && aws_instance.proxy.private_ip == "10.42.0.11"
    error_message = "the proxy is not a machine of its own, at the address the control plane trusts"
  }
}

run "the_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket.volumes.object_lock_enabled && aws_s3_bucket_versioning.volumes.versioning_configuration[0].status == "Enabled"
    error_message = "the bucket is not versioned under Object Lock"
  }
  assert {
    condition     = aws_s3_bucket_object_lock_configuration.volumes.rule[0].default_retention[0].mode == "GOVERNANCE"
    error_message = "the lock is not GOVERNANCE"
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.volumes.block_public_acls,
      aws_s3_bucket_public_access_block.volumes.block_public_policy,
      aws_s3_bucket_public_access_block.volumes.ignore_public_acls,
      aws_s3_bucket_public_access_block.volumes.restrict_public_buckets,
    ])
    error_message = "the bucket may be made public"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.bucket.statement :
    s.effect == "Deny" && contains(s.actions, "s3:GetObject*") && anytrue([for c in s.condition : c.variable == "aws:SourceVpce"])])
    error_message = "objects are not refused outside the VPC's endpoint"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.bucket.statement :
    s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport"])])
    error_message = "the bucket answers without TLS"
  }
}

run "the_roles" {
  command = plan

  assert {
    condition = alltrue([for arn in [
      aws_iam_role.controlplane.permissions_boundary, aws_iam_role.runner_scope.permissions_boundary,
      aws_iam_role.proxy.permissions_boundary, aws_iam_role.dlm.permissions_boundary,
      aws_iam_role.flow[0].permissions_boundary,
    ] : arn == "arn:aws:iam::123456789012:policy/spin-boundary"])
    error_message = "a role carries no boundary"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "iam:PassRole") && contains(s.actions, "iam:Attach*")])
    error_message = "the boundary lets a role write IAM"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "sts:AssumeRole") && s.not_resources == toset(["arn:aws:iam::123456789012:role/spin-runner-scope"])])
    error_message = "the boundary lets a role become another than the runner scope"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "ec2:*SecurityGroup*")])
    error_message = "the boundary lets a role open a security group"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    s.effect == "Deny" && contains(s.actions, "s3:BypassGovernanceRetention") && contains(s.actions, "s3:PutBucketPolicy")])
    error_message = "the control plane can lift the bucket's lock or rewrite its policy"
  }
  assert {
    condition     = aws_iam_role.runner_scope.max_session_duration == 3600
    error_message = "a runner's credential can outlive its hour"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.proxy.statement :
    s.actions == toset(["ssm:GetParameter"])])
    error_message = "the proxy's role may do more than read the CA"
  }
}

run "the_logs" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc[0].traffic_type == "ALL" && aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "the flow log is not every connection, or is kept for ever"
  }
}
