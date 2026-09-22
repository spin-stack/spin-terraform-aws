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
  target = aws_iam_policy.session_manager
  values = { arn = "arn:aws:iam::123456789012:policy/spin-session-manager" }
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

# What the machines' user data names, known here so it can be read at plan.
override_resource {
  target = aws_route53_zone.internal
  values = { zone_id = "Z0SPININTERNAL", arn = "arn:aws:route53:::hostedzone/Z0SPININTERNAL" }
}

override_resource {
  target = aws_s3_bucket.certificates
  values = { arn = "arn:aws:s3:::spin-proxy-123456789012-us-east-2" }
}

override_resource {
  target = aws_vpc.this
  values = { id = "vpc-0spin" }
}

override_resource {
  target = aws_eip.proxy
  values = { allocation_id = "eipalloc-0123456789abcdef0", public_ip = "203.0.113.10" }
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
    condition = alltrue([for t in [aws_launch_template.controlplane, aws_launch_template.proxy] :
    t.metadata_options[0].http_tokens == "required" && t.metadata_options[0].http_put_response_hop_limit == 1])
    error_message = "a machine answers IMDSv1, or its role is reachable from further than the machine itself"
  }
  assert {
    condition = alltrue([for t in [aws_launch_template.controlplane, aws_launch_template.proxy] :
    t.block_device_mappings[0].ebs[0].encrypted == "true"]) && aws_db_instance.catalog.storage_encrypted
    error_message = "a disk is not encrypted"
  }
  # The proxy in subnets of its own, which are what the control plane trusts a browser's
  # address from: a runner or the control plane itself is never among them.
  assert {
    condition = length(setintersection(toset(aws_subnet.edge[*].cidr_block), toset(concat(aws_subnet.public[*].cidr_block, aws_subnet.database[*].cidr_block)))) == 0 && strcontains(local.controlplane_user_data,
    "--trusted-proxy '10.42.136.0/24,10.42.137.0/24,10.42.138.0/24'")
    error_message = "the control plane takes a browser's address from somewhere a proxy is not alone"
  }
}

# One of each, replaced beside itself: an update starts the new machine before it retires the
# old, and holds the old until the new one says it serves.
run "an_update_stands_the_new_machine_beside_the_old" {
  command = plan

  assert {
    condition = alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] :
      g.desired_capacity == 1 && g.max_size == 2 && g.instance_refresh[0].preferences[0].min_healthy_percentage == 100 &&
    g.instance_refresh[0].preferences[0].max_healthy_percentage == 200])
    error_message = "an update retires a machine before its replacement is up"
  }
  assert {
    condition = alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] :
    anytrue([for h in g.initial_lifecycle_hook : h.lifecycle_transition == "autoscaling:EC2_INSTANCE_LAUNCHING" && h.default_result == "ABANDON"])])
    error_message = "a machine that never comes up replaces the one that works"
  }
  # Terraform waiting for a machine is Terraform giving up on a slow boot, marking the group as
  # half-created, and destroying it on the next apply - a group whose only problem was that a
  # first boot takes longer than the wait. The hook is what decides, and it abandons.
  assert {
    condition = alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] :
    g.wait_for_capacity_timeout == "0"])
    error_message = "an apply waits for a machine, so a slow boot has the next one destroy the group"
  }
  # A hook the provider gives at creation and never reads back reads as absent, and it answers
  # that by replacing the group: taking the installation down to change nothing.
  # lifecycle is not an attribute a plan can be asked about, so the files are.
  assert {
    condition = alltrue([for f in ["instance.tf", "proxy.tf"] :
    strcontains(file("${path.module}/${f}"), "ignore_changes = [initial_lifecycle_hook]")])
    error_message = "a hook nothing reads back can have the group replaced under the installation"
  }
  # The new control plane takes its name before the term, and says it serves only once it
  # leads; a proxy takes the address once Caddy answers.
  assert {
    condition = (
      strcontains(local.controlplane_user_data, "point 'cp.spin.internal'\nSPIN_CP_DATABASE_URL=") &&
      strcontains(local.controlplane_user_data, "\nin_service\nserving=yes\nsystemctl enable --now spin-controlplane-watchdog.timer") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "point 'proxy.spin.internal'\naws --region 'us-east-2' ec2 associate-address --allocation-id 'eipalloc-0123456789abcdef0'")
    )
    error_message = "a new machine takes the installation over in another order than name, then service"
  }
  # Until it is in service, a new control plane that fails hands the installation back: its own
  # control plane stopped, the name where it was, the launch abandoned; and the old machine's
  # watchdog serves the name it is given back, and takes back one nobody answers at. The trap is
  # set before anything that can fail but the machine's packages - a release it cannot fetch
  # abandons the launch at once rather than holding the group for the hook's half an hour.
  assert {
    condition = (
      strcontains(local.controlplane_user_data, ". /usr/local/lib/spin/lifecycle.sh\nprevious=\nserving=\nhand_back() {") &&
      strcontains(local.controlplane_user_data, "point 'cp.spin.internal' \"$previous\" || true\n  fi\n  abandon || true") &&
      strcontains(local.controlplane_user_data, "trap hand_back EXIT\n\n# --- the encryption key") &&
      strcontains(local.controlplane_user_data, "previous=$(resolve 'cp.spin.internal')\npoint 'cp.spin.internal'\n") &&
      strcontains(local.controlplane_files["/usr/local/sbin/spin-controlplane-watchdog"].content, "if [ \"$at\" = \"$self\" ]; then") &&
      strcontains(local.controlplane_files["/usr/local/sbin/spin-controlplane-watchdog"].content, "point \"$name\"\n  systemctl start spin-controlplane.service")
    )
    error_message = "a failed replacement leaves the installation's name at a machine that is not serving it"
  }
  # A new proxy that fails does the same from its first step: the name back where it pointed,
  # the address back on the proxy of this VPC that answers there, the launch abandoned.
  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.proxy.user_data), ". /usr/local/lib/spin/lifecycle.sh\n\n# Until this machine is in service") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "trap hand_back EXIT\n\n# release <version> <file>") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "point 'proxy.spin.internal' \"$previous\" || true") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "'Name=vpc-id,Values=vpc-0spin' \"Name=private-ip-address,Values=$previous\"") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "--instance-id \"$old\" --allow-reassociation >/dev/null || true\n    fi\n  fi\n  abandon || true") &&
      strcontains(base64decode(aws_launch_template.proxy.user_data), "\nin_service\nserving=yes\n")
    )
    error_message = "a failed proxy replacement leaves the name or the address at a machine that is not serving them"
  }
  # The first machine asks where the name points before it exists: an answer of nothing, and not
  # a failure that set -e and pipefail would end the boot on.
  assert {
    condition     = strcontains(local.controlplane_files["/usr/local/lib/spin/lifecycle.sh"].content, "{ getent ahostsv4 \"$1\" || true; } | awk")
    error_message = "resolving a name that does not exist yet ends the first machine's boot"
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.proxy.user_data), "runuser -u spin-proxy -- /usr/local/sbin/spin-proxy-certificates restore\n\nspin-install proxy")
    error_message = "a new proxy starts Caddy before it has the certificates the last one had, or restores them as root"
  }
}

# The encryption key is kept before anything uses it: stored in SSM without overwriting one that
# is there, and then read back, so a first machine that dies has lost nothing and two racing end
# on one key.
run "the_encryption_key_is_kept_before_it_is_used" {
  command = plan

  assert {
    condition = can(regex(
      "(?s)put-parameter --name '/spin/controlplane-encryption-key' --type SecureString --value \"file://\\$file\" \\\\\n.*stored=\\$\\(key\\).*SPIN_CP_ENCRYPTION_KEY=.*spin-install control-plane",
      local.controlplane_user_data,
    ))
    error_message = "the encryption key is used before it is stored, or is not the stored one"
  }
  assert {
    condition     = !can(regex("put-parameter --name '/spin/controlplane-encryption-key'[^\n]*--overwrite", local.controlplane_user_data)) && length(regexall("put-parameter --name '/spin/controlplane-encryption-key'", local.controlplane_user_data)) == 1
    error_message = "the encryption key can be overwritten, or is written more than once"
  }
  # The key is the file's secret, not the directory's: the control plane runs as its own user
  # and opens the database's CA in that same directory, which spin-install writes 0644.
  assert {
    condition = (
      strcontains(local.controlplane_user_data, "install -d -m 0755 /etc/spin-stack\n(umask 077; printf 'SPIN_CP_ENCRYPTION_KEY=") &&
      !strcontains(local.controlplane_user_data, "install -d -m 0700 /etc/spin-stack")
    )
    error_message = "/etc/spin-stack is a directory the control plane's user cannot enter, so it cannot read the CA its catalog is verified by"
  }
}

# Caddy's directory is copied as Caddy's user, and links in it are not followed: as root, a link
# Caddy planted would have the copy read any file of the machine into the bucket.
run "the_certificates_are_copied_with_caddys_rights" {
  command = plan

  assert {
    condition = (
      strcontains(local.proxy_files["/etc/systemd/system/spin-proxy-certificates.service"].content, "\nUser=spin-proxy\n") &&
      strcontains(local.proxy_files["/usr/local/sbin/spin-proxy-certificates"].content, "--no-follow-symlinks") &&
      strcontains(local.proxy_files["/usr/local/sbin/spin-proxy-certificates"].content, "if [ \"$(id -u)\" -eq 0 ]; then")
    )
    error_message = "the certificates are copied as root, or links in Caddy's directory are followed"
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
    condition     = strcontains(local.controlplane_user_data, "\"TTL\":%d") && strcontains(local.controlplane_user_data, "'10'")
    error_message = "a replaced machine's name is kept by clients longer than ten seconds"
  }
  assert {
    condition     = strcontains(local.controlplane_user_data, "--advertise 'cp.spin.internal'") && output.url == "https://cp.spin.internal:8080"
    error_message = "the control plane's certificate does not carry the name it is reached by"
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.proxy.user_data), "--control-plane 'https://cp.spin.internal:8080'") && output.relay_dial == "proxy.spin.internal:443"
    error_message = "the proxy, or the runners' relay, is dialled by something other than its name"
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
  # What a machine moves to itself is its own name and the proxy's one address, and no more: the
  # role grants that alone, and the boundary refuses any other zone or address whatever is
  # granted.
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.proxy.statement :
      !contains(s.actions, "route53:ChangeResourceRecordSets") || (length(s.condition) > 0 && alltrue([for c in s.condition :
    toset(c.values) == toset(["proxy.spin.internal"])]))])
    error_message = "the proxy may write a name other than its own"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane.statement :
      !contains(s.actions, "route53:ChangeResourceRecordSets") || (length(s.condition) > 0 && alltrue([for c in s.condition :
    toset(c.values) == toset(["cp.spin.internal"])]))])
    error_message = "the control plane may write a name other than its own"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "route53:*") && s.not_resources == toset(["arn:aws:route53:::hostedzone/Z0SPININTERNAL"])]) && anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "ec2:*Address*") && contains(s.not_resources, "arn:aws:ec2:us-east-2:123456789012:elastic-ip/eipalloc-0123456789abcdef0")])
    error_message = "the boundary lets a role write another zone, or take another address"
  }
  assert {
    condition = !anytrue([for s in data.aws_iam_policy_document.proxy.statement :
    anytrue([for a in s.actions : startswith(a, "s3:") && !contains(s.resources, "arn:aws:s3:::spin-proxy-123456789012-us-east-2")])])
    error_message = "the proxy's role reaches a bucket other than its certificates'"
  }
}

# No machine but the control plane's reads its secrets: Session Manager comes with nothing else
# of SSM, and the boundary refuses the encryption key and the collector's token to any other
# role, whatever policy it is given later.
run "no_machine_reads_the_control_planes_secrets" {
  command = plan

  assert {
    condition = alltrue([for a in [aws_iam_role_policy_attachment.controlplane_ssm, aws_iam_role_policy_attachment.proxy_ssm] :
    !strcontains(a.policy_arn, "AmazonSSMManagedInstanceCore")])
    error_message = "a machine is given the managed policy that reads every parameter"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.session_manager.statement :
    alltrue([for a in s.actions : startswith(a, "ssmmessages:") || a == "ssm:UpdateInstanceInformation"])])
    error_message = "Session Manager's policy grants more of SSM than a session"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "ssm:GetParameter*") &&
      contains(s.resources, "arn:aws:ssm:us-east-2:123456789012:parameter/spin/controlplane-encryption-key") &&
      anytrue([for c in s.condition : c.test == "ArnNotEquals" && c.variable == "aws:PrincipalArn" &&
    toset(c.values) == toset(["arn:aws:iam::123456789012:role/spin-controlplane"])])])
    error_message = "a role other than the control plane's can read the encryption key"
  }
}

run "no_collector_unless_asked" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.grafana_token) == 0 && length(aws_vpc_security_group_ingress_rule.collector_from_proxy) == 0
    error_message = "a collector's token or port exists on an installation that ships no telemetry"
  }
  assert {
    condition     = !strcontains(local.controlplane_user_data, "alloy") && !strcontains(local.controlplane_user_data, "--otel-collector")
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
    condition     = strcontains(local.controlplane_user_data, "printf '%s  %s\\n' '${var.grafana_cloud.alloy_sha256}'") && strcontains(local.controlplane_user_data, "--otel-collector 'cp.spin.internal:4317' --otel-metric-interval '60s'")
    error_message = "the collector is installed unchecked, or the control plane is not pointed at it"
  }
  assert {
    condition     = strcontains(base64decode(aws_launch_template.proxy.user_data), "--otel-collector 'cp.spin.internal:4317'")
    error_message = "the proxy is not pointed at the collector"
  }
  assert {
    condition     = !strcontains(local.controlplane_user_data, "glc_") && strcontains(local.controlplane_user_data, "/spin/grafana-cloud-token")
    error_message = "the token is in the user data rather than read from SSM"
  }
  # EC2 refuses user data over 16 KiB, and says so at launch rather than at plan.
  assert {
    condition     = startswith(aws_launch_template.controlplane.user_data, "H4sI") && length(aws_launch_template.controlplane.user_data) * 3 / 4 < 16384
    error_message = "the control plane's user data is not gzipped, or is over the 16 KiB EC2 takes even so"
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
  # The master is a member of spin for the one statement that hands the database over, and not
  # after it: rds_iam reaches the master through that membership, and RDS takes no password from
  # a user it knows as an IAM one - the next boot could not sign in to run this file at all.
  assert {
    condition = strcontains(local.controlplane_files["/etc/spin-stack/database-bootstrap.sql"].content,
    "GRANT spin TO CURRENT_USER;\nALTER DATABASE spin OWNER TO spin;\nREVOKE spin FROM CURRENT_USER;")
    error_message = "the master keeps its membership of spin, and with it an rds_iam that stops its password working"
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
    condition     = strcontains(local.controlplane_user_data, "--database-auth aws-iam") && strcontains(local.controlplane_user_data, "sslmode=verify-full")
    error_message = "the control plane signs in with a password, or does not check the catalog's certificate"
  }
}

# Every machine runs what the release workflow signed, checked with a cosign pinned by its hash,
# and nothing that is an image.
run "the_machines_run_what_the_release_signed" {
  command = plan

  assert {
    condition = alltrue([for u in [local.controlplane_user_data, base64decode(aws_launch_template.proxy.user_data)] :
      strcontains(u, "cosign verify-blob") && strcontains(u, "release.yml@refs/tags/$1\"") &&
    strcontains(u, var.cosign.sha256) && !strcontains(u, "docker")]) && output.fetch_release == local.fetch_release
    error_message = "a machine runs what it has not checked against the release's signature, or runs a container"
  }
  assert {
    condition     = strcontains(local.controlplane_user_data, "release 'v20260921.02' spin-controlplane-linux-amd64.tar.gz") && strcontains(base64decode(aws_launch_template.proxy.user_data), "release 'v20260921.02' spin-proxy-linux-amd64.tar.gz")
    error_message = "a machine unpacks another role's tarball, or another release's"
  }
  # The files come from the release's public package, with an oras pinned like cosign: spin's
  # repository is private, and a download from its releases is a 404 to a machine.
  assert {
    condition = (
      # With a home: a first boot has no HOME, and oras refuses to start without one.
      strcontains(local.fetch_release, "HOME=\"$${HOME:-/root}\" oras pull --no-tty \"ghcr.io/spin-stack/spin-release:$1-$${2%.tar.gz}\"\n  cosign verify-blob") &&
      strcontains(local.fetch_release, "printf '%s  %s\\n' '${var.oras.sha256}' /tmp/oras.tar.gz | sha256sum --check") &&
      !strcontains(local.fetch_release, "spin-stack/spin/releases/download")
    )
    error_message = "a machine fetches the release from somewhere it cannot read, or runs an oras it has not checked"
  }
  # EC2 refuses user data over 16 KiB, and says so at launch rather than at plan.
  assert {
    condition     = length(aws_launch_template.controlplane.user_data) * 3 / 4 < 16384 && length(base64decode(aws_launch_template.proxy.user_data)) < 16384
    error_message = "a machine's user data is over the 16 KiB EC2 takes"
  }
}

run "the_logs" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc[0].traffic_type == "ALL" && aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "the flow log is not every connection, or is kept for ever"
  }
}
