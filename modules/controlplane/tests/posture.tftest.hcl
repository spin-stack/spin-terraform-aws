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
  target = data.aws_ec2_instance_type.controlplane
  values = { default_vcpus = 2 }
}

override_data {
  target = data.aws_ec2_instance_type.proxy
  values = { default_vcpus = 2 }
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

override_resource {
  target = aws_ssm_parameter.proxy_config
  values = { arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/proxy-config" }
}

# The image the release's machines boot, which is known once it is applied.
override_resource {
  target = terraform_data.image
  values = { output = "ami-0123456789abcdef0" }
}

# The CA's certificate, which the proxy's and the runners' documents carry.
override_resource {
  target = tls_self_signed_cert.ca
  values = { cert_pem = "-----BEGIN CERTIFICATE-----\nthe installation's CA\n-----END CERTIFICATE-----\n" }
}

variables {
  spin_version = "v20260921.02"
  domain       = "example.com"
  # The digest of that release's spin-boot: what a machine checks the one file it fetches
  # against.
  spin_boot_sha256 = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
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
  # address from: a runner or the control plane itself is never among them. Declared in the
  # installation's configuration rather than installed on the machine, so the day this edge
  # changes is an apply.
  assert {
    condition     = length(setintersection(toset(aws_subnet.edge[*].cidr_block), toset(concat(aws_subnet.public[*].cidr_block, aws_subnet.database[*].cidr_block)))) == 0
    error_message = "the proxy's subnets are not its own"
  }
  assert {
    condition     = toset(local.installation.settings.trusted_proxies) == toset(aws_subnet.edge[*].cidr_block)
    error_message = "the control plane takes a browser's address from somewhere a proxy is not alone"
  }
  assert {
    condition     = !strcontains(local.user_data["control-plane"], "--trusted-proxy") && !strcontains(yamlencode(local.controlplane_document), "trusted")
    error_message = "a machine is installed with who may name a browser, which is the installation's to say"
  }
}

# What a machine's user data is: spin-boot fetched by the digest this module pins, checked, and
# run over the role's document - and nothing else. Every step a boot takes is spin-boot's, in Go
# with tests; a line added here is a step nobody can test, whose failure is on a disk the group
# throws away.
run "a_machines_user_data_is_spin_boot_and_nothing_else" {
  command = plan

  assert {
    condition = alltrue([for role, u in local.user_data : (
      strcontains(u, "/v2/$repo/blobs/sha256:${var.spin_boot_sha256}\"") &&
      strcontains(u, "echo '${var.spin_boot_sha256}  /usr/local/bin/spin-boot' | sha256sum --check --quiet") &&
      endswith(u, "exec /usr/local/bin/spin-boot ${role} --config 'ssm:///spin/${role == "control-plane" ? "controlplane" : role}-config?region=us-east-2'\n") &&
      length(regexall("\n[^#\n]", u)) <= 7
    )])
    error_message = "a machine's user data does more than fetch spin-boot by its digest and run it over its document"
  }
  assert {
    condition = alltrue([for u in values(local.user_data) : alltrue([for never in ["aws ", "systemctl", "apt-get", "python", "put-parameter", "spin-controlplane", "spin-install"] :
    !strcontains(u, never)])])
    error_message = "a machine's user data calls a cloud, a package manager or systemd itself"
  }
  assert {
    condition = (
      base64decode(aws_launch_template.controlplane.user_data) == local.user_data["control-plane"] &&
      base64decode(aws_launch_template.proxy.user_data) == local.user_data["proxy"] &&
      output.runner_user_data == local.user_data["runner"]
    )
    error_message = "a machine is launched with other user data than its role's"
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
  # The hook's timeout is how long a machine may say nothing, not how long a boot may take: a
  # machine that dies - or that somebody terminated - is abandoned in minutes, and a first boot
  # that needs half an hour beats its way through it.
  assert {
    condition = alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] :
    anytrue([for h in g.initial_lifecycle_hook : h.heartbeat_timeout == 300])])
    error_message = "the hook waits out a long silence, so a machine that is gone holds the group"
  }
  # The boot beats more often than the hook's timeout, in the group and at the hook the group
  # holds the machine by; the order a machine takes the installation over in, and how it hands
  # it back, are spin-boot's and tested there (spin's internal/boot).
  assert {
    condition = alltrue([for d in [local.controlplane_document, local.proxy_document] : (
      d.install.launch.aws.heartbeat == "60s" && d.install.launch.aws.hook == "ready" &&
      contains([local.controlplane_group, local.proxy_group], d.install.launch.aws.group)
    )]) && alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] : anytrue([for h in g.initial_lifecycle_hook : h.name == "ready"])])
    error_message = "a boot says nothing while it works, or to a hook its group does not have, so its own silence is what abandons it"
  }
  # A change to what a machine starts on is a new template, which the refresh rolls out; one
  # whose machine never comes into service puts the group back on the template it had.
  assert {
    condition = (
      aws_launch_template.controlplane.tag_specifications[0].tags["spin:starts-on"] == sha256(join("\n", [yamlencode(local.controlplane_document), yamlencode(local.installation)])) &&
      aws_launch_template.proxy.tag_specifications[0].tags["spin:starts-on"] == sha256(yamlencode(local.proxy_document)) &&
      alltrue([for g in [aws_autoscaling_group.controlplane, aws_autoscaling_group.proxy] : g.instance_refresh[0].preferences[0].auto_rollback])
    )
    error_message = "a change to a document reaches no machine until something replaces it, or a failed update is left as the group's template"
  }
  # The image is the one of the release, not the newest on whatever day an apply runs.
  assert {
    condition     = aws_launch_template.controlplane.image_id == terraform_data.image.output && aws_launch_template.proxy.image_id == terraform_data.image.output
    error_message = "the machines boot an image an unrelated apply picked"
  }
  # Each machine takes its own name, in the installation's zone, and the proxy its address.
  assert {
    condition = (
      local.controlplane_document.install.launch.aws.name == "cp.spin.internal" &&
      local.proxy_document.install.launch.aws.name == "proxy.spin.internal" &&
      local.controlplane_document.install.launch.aws.zone == "Z0SPININTERNAL" &&
      local.proxy_document.install.launch.aws.elastic_ip == "eipalloc-0123456789abcdef0" &&
      !contains(keys(local.controlplane_document.install.launch.aws), "elastic_ip")
    )
    error_message = "a machine takes a name or an address that is not its role's"
  }
  # The domain is given to this module and then to the installation: an installation that has
  # none takes every browser origin but localhost for another site, so the dashboard loads and a
  # workspace's terminal is refused — with the operator asked, in the setup pages, for the one
  # thing they had already said here.
  assert {
    condition     = local.installation.base_domain == "example.com" && local.proxy_document.domain == "example.com"
    error_message = "the installation is never told the domain it answers on"
  }
}

# The installation's secrets are this apply's to write and nobody else's. The key and the first
# administrator's password are ephemeral and written through write-only attributes, so neither is
# in the plan or the state; each is written once, on the version this module fixes, and an apply
# after that writes neither again - a new key is a catalog nothing can open.
run "the_secrets_are_written_once_and_never_by_a_machine" {
  command = plan

  assert {
    condition = (
      aws_ssm_parameter.encryption_key.type == "SecureString" && aws_ssm_parameter.encryption_key.value_wo_version == 1 &&
      aws_ssm_parameter.admin_password.type == "SecureString" && aws_ssm_parameter.admin_password.value_wo_version == 1 &&
      strcontains(file("${path.module}/secrets.tf"), "ephemeral \"random_password\" \"encryption_key\"") &&
      strcontains(file("${path.module}/secrets.tf"), "ephemeral \"random_password\" \"admin\"")
    )
    error_message = "the encryption key or the administrator's password is in the state, or is written on every apply"
  }
  # A plan that would make the key or the CA again is refused: a new key is a catalog nothing
  # opens, a new CA every runner distrusting the control plane. lifecycle is not an attribute a
  # plan can be asked about, so the file is.
  assert {
    condition     = length(regexall("prevent_destroy = true", file("${path.module}/secrets.tf"))) == 3
    error_message = "the key or the CA can be replaced by an apply"
  }
  # The CA the control plane issues under, and the certificate everything else trusts it by: a CA
  # that can sign, and nothing but the certificate in a document another role reads.
  assert {
    condition = (
      tls_self_signed_cert.ca.is_ca_certificate && contains(tls_self_signed_cert.ca.allowed_uses, "cert_signing") &&
      tls_self_signed_cert.ca.early_renewal_hours == 0 &&
      aws_ssm_parameter.ca.type == "SecureString" &&
      local.controlplane_document.tls.ca_at == "ssm:///spin/controlplane-ca?region=us-east-2" &&
      !strcontains(yamlencode(local.proxy_document), "PRIVATE KEY") && !strcontains(yamlencode(local.runner_document), "PRIVATE KEY")
    )
    error_message = "the CA cannot sign, would be made again by an apply, or its key is in a document another role reads"
  }
  # Named in the control plane's document and read by it; nothing reads them on a machine's behalf.
  assert {
    condition = (
      local.controlplane_document.encryption_key_at == "ssm:///spin/controlplane-encryption-key?region=us-east-2" &&
      local.controlplane_document.bootstrap_admin.password_at == "ssm:///spin/bootstrap-password?region=us-east-2" &&
      local.controlplane_document.bootstrap_admin.email == "admin@example.com" &&
      !contains(keys(local.controlplane_document), "encryption_key")
    )
    error_message = "the document holds a secret rather than where it is"
  }
  # No role of the installation writes a parameter, whatever policy it is given later.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "ssm:PutParameter") && contains(s.actions, "ssm:DeleteParameter*") &&
    s.resources == toset(["*"]) && length(s.condition) == 0])
    error_message = "a machine of the installation can write a parameter another machine starts on"
  }
  assert {
    condition = !anytrue([for d in [data.aws_iam_policy_document.controlplane, data.aws_iam_policy_document.proxy] :
    anytrue([for s in d.statement : s.effect != "Deny" && anytrue([for a in s.actions : startswith(a, "ssm:") && a != "ssm:GetParameter"])])])
    error_message = "a machine's role is granted more of SSM than reading its parameters"
  }
}

# What a machine starts on is one document in the parameter store, and the machine is told where
# it is and nothing else: no value in the document is also a flag on the machine, which is a fact
# in two places where the one that loses loses silently.
run "the_installation_is_in_its_document_and_not_on_its_machines" {
  command = plan

  assert {
    condition = (
      local.controlplane_document.database.auth == "aws-iam" &&
      !can(regex("password", local.controlplane_document.database.url)) &&
      local.controlplane_document.production &&
      local.controlplane_document.tls.extra_sans == ["cp.spin.internal"]
    )
    error_message = "the document does not say what the control plane needs before it can read its catalog"
  }
  assert {
    condition = (
      aws_ssm_parameter.controlplane_config.type == "String" && aws_ssm_parameter.controlplane_config.value == yamlencode(local.controlplane_document) &&
      aws_ssm_parameter.proxy_config.type == "String" && aws_ssm_parameter.proxy_config.value == yamlencode(local.proxy_document) &&
      aws_ssm_parameter.runner_config.type == "String" && aws_ssm_parameter.runner_config.value == yamlencode(local.runner_document)
    )
    error_message = "a document is not what its parameter holds"
  }
  # The installation's own configuration is read by the control plane at every start, which makes
  # the catalog match it: nothing applies it by hand on a machine.
  assert {
    condition = (
      local.controlplane_document.installation_at == "ssm:///spin/installation?region=us-east-2" &&
      aws_ssm_parameter.installation.value == yamlencode(local.installation) &&
      aws_ssm_parameter.installation.type == "SecureString"
    )
    error_message = "the installation's configuration is not where its control plane reads it"
  }
  # What the release this machine installs and the store its volumes live in are: in the document,
  # so that the user data holds neither. A runner's release is its control plane's, asked of it.
  assert {
    condition = (
      local.controlplane_document.install.release == "v20260921.02" &&
      local.proxy_document.install.release == "v20260921.02" &&
      !contains(keys(local.runner_document.install), "release") &&
      local.controlplane_document.install.store.bucket == "spin-volumes-123456789012-us-east-2" &&
      startswith(local.controlplane_document.install.store.role_arn, "arn:aws:iam::123456789012:role/")
    )
    error_message = "a document does not say what its machine installs, or a runner is told a release other than its control plane's"
  }
}

# A runner joins by who it is: its role, for this installation. The installation names the role
# and the policy its machines start under, and the runner's document the same audience; there is
# no token to mint, publish or read.
run "a_runner_joins_by_its_role" {
  command = plan

  assert {
    condition = (
      local.installation.host_join.audience == "spin:123456789012:spin" &&
      local.runner_document.install.join.audience == local.installation.host_join.audience &&
      local.installation.host_join.aws == [{ role = "arn:aws:iam::123456789012:role/spin-runner", shutdown_grace = "100s", preemption_source = "aws" }]
    )
    error_message = "a runner joins for another installation than the one that names its role, or under no policy"
  }
  assert {
    condition     = !strcontains(yamlencode(local.runner_document), "token")
    error_message = "a runner is told where a token is"
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
    condition     = aws_route53_zone.public.name == var.domain && length(aws_route53_zone.public.vpc) == 0
    error_message = "the domain's zone is not a public one of its own"
  }
  assert {
    condition     = toset(keys(aws_route53_record.app)) == toset(["app.${var.domain}", "*.app.${var.domain}"])
    error_message = "the dashboard and the workspaces' names are not written into the domain's zone"
  }
  assert {
    condition     = local.controlplane_document.install.launch.aws.ttl == 10 && local.proxy_document.install.launch.aws.ttl == 10
    error_message = "a replaced machine's name is kept by clients longer than ten seconds"
  }
  assert {
    condition     = local.controlplane_document.tls.extra_sans == ["cp.spin.internal"] && output.url == "https://cp.spin.internal:8080"
    error_message = "the control plane's certificate does not carry the name it is reached by"
  }
  assert {
    condition = (
      local.proxy_document.control_plane == "https://cp.spin.internal:8080" &&
      local.runner_document.control_plane == "https://cp.spin.internal:8080" &&
      local.runner_document.relay_dial == "proxy.spin.internal:443" && output.relay_dial == "proxy.spin.internal:443"
    )
    error_message = "the control plane, or the runners' relay, is dialled by something other than its name"
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
  # The CA's key, the first administrator's password and the installation's configuration are
  # the same line as the encryption key: nobody else's to read.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "ssm:GetParameter*") && length(setintersection(s.resources, toset([
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/controlplane-ca",
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/bootstrap-password",
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/installation",
    ]))) == 3])
    error_message = "a role other than the control plane's can read the CA's key, the administrator's password or the installation's configuration"
  }
  # Each of the other machines reads its own document and nothing else of SSM.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.proxy.statement :
      s.actions == toset(["ssm:GetParameter"]) && length(s.resources) == 1]) && alltrue([for s in data.aws_iam_policy_document.proxy.statement :
    !anytrue([for a in s.actions : startswith(a, "ssm:")]) || s.resources == toset([aws_ssm_parameter.proxy_config.arn])])
    error_message = "the proxy reads more of SSM than its document"
  }
}

run "no_collector_unless_asked" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.grafana_token) == 0 && length(aws_vpc_security_group_ingress_rule.collector_from_proxy) == 0
    error_message = "a collector's token or port exists on an installation that ships no telemetry"
  }
  assert {
    condition     = local.controlplane_document.install.collector == null && !local.runner_document.telemetry.enabled && !local.proxy_document.telemetry.enabled
    error_message = "the control plane installs a collector nobody asked for, or a component pushes to one"
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
    condition = (
      local.controlplane_document.install.collector.alloy.sha256 == var.grafana_cloud.alloy_sha256 &&
      # Declared in the installation's own configuration, not in what the control plane starts
      # on: an installation is not asked for a collector before it has one.
      local.installation.settings.telemetry_collector == "cp.spin.internal:4317" &&
      local.installation.settings.telemetry_metric_interval == "60s" &&
      !contains(keys(local.controlplane_document), "telemetry")
    )
    error_message = "the collector is installed unchecked, or the control plane is not pointed at it"
  }
  assert {
    condition = alltrue([for d in [local.proxy_document, local.runner_document] :
    d.telemetry.enabled && d.telemetry.endpoint == "cp.spin.internal:4317" && d.telemetry.metric_interval == "60s"])
    error_message = "the proxy or the runners are not pointed at the collector"
  }
  # The token is the operator's, written where only the control plane reads it: the document says
  # where, and the plan never holds it.
  assert {
    condition = (
      local.controlplane_document.install.collector.token_at == "ssm:///spin/grafana-cloud-token?region=us-east-2" &&
      anytrue([for s in data.aws_iam_policy_document.controlplane.statement : contains(s.resources, "arn:aws:ssm:us-east-2:123456789012:parameter/spin/grafana-cloud-token")])
    )
    error_message = "the token is not where the collector reads it"
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
  # The first boot makes the role the control plane signs in as, as RDS's master, whose password
  # RDS keeps: the document names the secret, and the control plane's role alone reads it.
  assert {
    condition = (
      local.controlplane_document.install.catalog.admin_user == "spin_admin" &&
      local.controlplane_document.install.catalog.admin_secret == "arn:aws:secretsmanager:us-east-2:123456789012:secret:rds!db-abc" &&
      anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
      s.actions == toset(["secretsmanager:GetSecretValue"]) && s.resources == toset(["arn:aws:secretsmanager:us-east-2:123456789012:secret:rds!db-abc"])])
    )
    error_message = "the first boot cannot make the catalog's role, or reads more of Secrets Manager than the master's password"
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
    condition     = local.controlplane_document.database.auth == "aws-iam" && strcontains(local.controlplane_document.database.url, "sslmode=verify-full")
    error_message = "the control plane signs in with a password, or does not check the catalog's certificate"
  }
}

# Every machine runs what the release workflow signed, and nothing that is an image. A machine
# fetches one file by the digest this module pins and hands the rest to it: spin-boot checks the
# release's signature itself, in Go, with tests (spin's internal/release). The file comes from
# the release's public package by that digest, so what the registry serves under a tag is never
# what decides; spin's repository is private, and its releases are a 404 to a machine.
run "the_machines_run_what_the_release_signed" {
  command = plan

  assert {
    condition = alltrue([for u in values(local.user_data) : (
      strcontains(u, "repo=spin-stack/spin-release\n") &&
      !strcontains(u, "spin-stack/spin/releases/download") &&
      !strcontains(u, "/manifests/") &&
      !strcontains(u, "cosign") && !strcontains(u, "oras") && !strcontains(u, "tar ") && !strcontains(u, "docker")
    )])
    error_message = "a machine runs something it did not check by digest, or is back to checking signatures in shell"
  }
}

run "the_logs" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc[0].traffic_type == "ALL" && aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "the flow log is not every connection, or is kept for ever"
  }
}
