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

# Known at plan, so what carries them can be asserted on: the roles' boundary, and the user
# data, which names the runner scope and the data volume.
override_resource {
  target = aws_iam_policy.boundary
  values = { arn = "arn:aws:iam::123456789012:policy/spin-boundary" }
}

override_resource {
  target = aws_iam_role.runner_scope
  values = { arn = "arn:aws:iam::123456789012:role/spin-runner-scope" }
}

override_resource {
  target = aws_db_instance.catalog
  values = {
    address            = "spin-catalog.c1a2b3c4d5e6.us-east-2.rds.amazonaws.com"
    port               = 5432
    resource_id        = "db-ABCDEFGHIJKLMNOP"
    master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-2:123456789012:secret:rds!db-abc", kms_key_id = "", secret_status = "active" }]
  }
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
    condition     = aws_instance.proxy.metadata_options[0].http_put_response_hop_limit == 1 && aws_instance.controlplane.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "the instance's role is reachable from further than the machine itself"
  }
  assert {
    condition     = aws_instance.controlplane.root_block_device[0].encrypted && aws_instance.proxy.root_block_device[0].encrypted && aws_db_instance.catalog.storage_encrypted
    error_message = "a disk is not encrypted"
  }
  assert {
    condition     = aws_instance.proxy.private_ip != aws_instance.controlplane.private_ip && aws_instance.proxy.private_ip == "10.42.0.11"
    error_message = "the proxy is not a machine of its own, at the address the control plane trusts"
  }
}

# The components dial each other by names only the VPC resolves, so a machine replaced is a
# record changed: the control plane's certificate carries its name, and the proxy and every
# runner are configured with it rather than an address.
run "the_components_reach_each_other_by_name" {
  command = plan

  assert {
    condition     = aws_route53_zone.internal.name == "spin.internal" && length(aws_route53_zone.internal.vpc) == 1
    error_message = "the installation's names are not a zone private to its VPC"
  }
  assert {
    condition     = aws_route53_record.internal["cp.spin.internal"].records == toset(["10.42.0.10"]) && aws_route53_record.internal["proxy.spin.internal"].records == toset(["10.42.0.11"])
    error_message = "a name does not hold its machine's address"
  }
  assert {
    condition     = alltrue([for r in aws_route53_record.internal : r.ttl <= 60])
    error_message = "a replaced machine waits more than a minute for the others to follow it"
  }
  assert {
    condition     = strcontains(aws_instance.controlplane.user_data, "--advertise 'cp.spin.internal'") && output.url == "https://cp.spin.internal:8080"
    error_message = "the control plane's certificate does not carry the name it is reached by"
  }
  assert {
    condition     = strcontains(aws_instance.proxy.user_data, "--control-plane 'https://cp.spin.internal:8080'")
    error_message = "the proxy dials the control plane by something other than its name"
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
      aws_iam_role.proxy.permissions_boundary,
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

run "no_collector_unless_asked" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.grafana_token) == 0 && length(aws_vpc_security_group_ingress_rule.collector_from_proxy) == 0
    error_message = "a collector's token or port exists on an installation that ships no telemetry"
  }
  assert {
    condition     = !strcontains(aws_instance.controlplane.user_data, "alloy") && !strcontains(aws_instance.controlplane.user_data, "--otel-collector")
    error_message = "the control plane installs a collector nobody asked for"
  }
}

run "a_collector_when_asked" {
  command = plan
  variables {
    grafana_cloud = {
      otlp_endpoint = "https://otlp-gateway-prod-us-west-0.grafana.net/otlp"
      instance_id   = "123456"
    }
  }

  assert {
    condition     = aws_ssm_parameter.grafana_token[0].type == "SecureString" && aws_ssm_parameter.grafana_token[0].value == "unpublished"
    error_message = "the token's parameter is not a SecureString the operator fills"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.collector_from_proxy[0].from_port == 4317 && aws_vpc_security_group_ingress_rule.collector_from_proxy[0].cidr_ipv4 == null
    error_message = "the collector's port is open to an address range rather than to the proxy"
  }
  assert {
    condition     = strcontains(aws_instance.controlplane.user_data, "printf '%s  %s\\n' '${var.grafana_cloud.alloy_sha256}'") && strcontains(aws_instance.controlplane.user_data, "--otel-collector 'cp.spin.internal:4317' --otel-metric-interval '60s'")
    error_message = "the collector is installed unchecked, or the control plane is not pointed at it"
  }
  assert {
    condition     = strcontains(aws_instance.proxy.user_data, "--otel-collector 'cp.spin.internal:4317'")
    error_message = "the proxy is not pointed at the collector"
  }
  assert {
    condition     = !strcontains(aws_instance.controlplane.user_data, "glc_") && strcontains(aws_instance.controlplane.user_data, "/spin/grafana-cloud-token")
    error_message = "the token is in the user data rather than read from SSM"
  }
  # EC2 refuses user data over 16 KiB, and says so at launch rather than at plan.
  assert {
    condition     = length(aws_instance.controlplane.user_data) < 16384
    error_message = "the control plane's user data is over the 16 KiB EC2 takes"
  }
}

# The catalog is RDS where only the control plane reaches it, and no password of it is in the
# plan: the master's is RDS's own in Secrets Manager, and the control plane signs in with a token.
run "the_catalog" {
  command = plan

  assert {
    condition     = !aws_db_instance.catalog.publicly_accessible && aws_db_instance.catalog.manage_master_user_password && aws_db_instance.catalog.iam_database_authentication_enabled && aws_db_instance.catalog.password == null
    error_message = "the catalog is reachable from outside, or has a password this plan knows"
  }
  assert {
    condition     = length(aws_subnet.database) >= 2 && alltrue([for s in aws_subnet.database : !s.map_public_ip_on_launch])
    error_message = "the catalog's subnets give out public addresses, or are fewer than the two zones RDS takes"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.database_from_controlplane.from_port == 5432 && aws_vpc_security_group_ingress_rule.database_from_controlplane.cidr_ipv4 == null
    error_message = "the catalog takes connections from an address range rather than the control plane"
  }
  assert {
    condition     = aws_db_instance.catalog.deletion_protection && !aws_db_instance.catalog.skip_final_snapshot && aws_db_instance.catalog.backup_retention_period >= 7
    error_message = "the catalog can be destroyed without a snapshot, or keeps less than a week to restore to"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    contains(s.actions, "rds-db:connect") && s.resources == toset(["arn:aws:rds-db:us-east-2:123456789012:dbuser:db-ABCDEFGHIJKLMNOP/spin"])])
    error_message = "the control plane signs in to the catalog as something other than spin"
  }
  assert {
    condition     = strcontains(aws_instance.controlplane.user_data, "--database-auth aws-iam") && strcontains(aws_instance.controlplane.user_data, "sslmode=verify-full")
    error_message = "the control plane signs in with a password, or does not check the catalog's certificate"
  }
}

# Every machine runs what the release workflow signed, checked with a cosign pinned by its hash,
# and nothing that is an image.
run "the_machines_run_what_the_release_signed" {
  command = plan

  assert {
    condition = alltrue([for u in [aws_instance.controlplane.user_data, aws_instance.proxy.user_data] :
      strcontains(u, "cosign verify-blob") && strcontains(u, "release.yml@refs/tags/v20260921.02") &&
    strcontains(u, var.cosign.sha256) && !strcontains(u, "docker")])
    error_message = "a machine runs what it has not checked against the release's signature, or runs a container"
  }
  assert {
    condition     = strcontains(aws_instance.controlplane.user_data, "release spin-controlplane-linux-amd64.tar.gz") && strcontains(aws_instance.proxy.user_data, "release spin-proxy-linux-amd64.tar.gz")
    error_message = "a machine unpacks another role's tarball"
  }
  # EC2 refuses user data over 16 KiB, and says so at launch rather than at plan.
  assert {
    condition     = length(aws_instance.controlplane.user_data) < 16384
    error_message = "the control plane's user data is over the 16 KiB EC2 takes"
  }
}

run "the_logs" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc[0].traffic_type == "ALL" && aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "the flow log is not every connection, or is kept for ever"
  }
}
