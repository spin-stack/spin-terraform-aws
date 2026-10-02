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

# The Spin OS image of the release, as spin-stack/ami registers one.
override_data {
  target = data.aws_ami.spin_os
  values = { id = "ami-0123456789abcdef0", root_device_name = "/dev/xvda" }
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

# Known at plan, so what carries them can be asserted on: the roles' boundary, and the user
# data, which names the runner scope and the data volume.
override_resource {
  target = aws_iam_policy.boundary
  values = { arn = "arn:aws:iam::123456789012:policy/spin-us-east-2-boundary" }
}

override_resource {
  target = aws_iam_policy.session_manager
  values = { arn = "arn:aws:iam::123456789012:policy/spin-us-east-2-session-manager" }
}

override_resource {
  target = aws_iam_role.runner_scope
  values = { arn = "arn:aws:iam::123456789012:role/spin-us-east-2-runner-scope" }
}

override_resource {
  target = aws_kms_key.identity
  values = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-0000-0000-000000000001" }
}

# The KMS key the control plane's key is agreed with, which its document names.
override_resource {
  target = aws_kms_key.encryption
  values = { arn = "arn:aws:kms:us-east-2:123456789012:key/00000000-0000-4000-8000-000000000002" }
}

# The buckets' ARNs, so what each role is given of which bucket can be read at plan.
override_resource {
  target = aws_s3_bucket.database
  values = { arn = "arn:aws:s3:::spin-database-123456789012-us-east-2" }
}

override_resource {
  target = aws_s3_bucket.volumes
  values = { arn = "arn:aws:s3:::spin-volumes-123456789012-us-east-2" }
}

override_resource {
  target = aws_s3_bucket.logs
  values = { arn = "arn:aws:s3:::spin-logs-123456789012-us-east-2" }
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
  values = { arn = "arn:aws:ssm:us-east-2:123456789012:parameter/spin/spin/proxy-config" }
}

# The CA's certificate, which the proxy's and the runners' documents carry.
override_resource {
  target = tls_self_signed_cert.ca
  values = { cert_pem = "-----BEGIN CERTIFICATE-----\nthe installation's CA\n-----END CERTIFICATE-----\n" }
}

variables {
  spin_version = "v20260921.02"
  domain       = "example.com"
  # A release images.json does not have, in a region it has none in: the images are named, and the
  # control plane's PCRs with them. The runs of the machines' images ask images.json.
  image_ids = {
    "control-plane" = "ami-0123456789abcdef0"
    runner          = "ami-0aaaaaaaaaaaaaaaa"
    proxy           = "ami-0bbbbbbbbbbbbbbbb"
  }
  image_measurements = {
    "control-plane" = {
      pcr4  = "444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444"
      pcr7  = "777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777"
      pcr12 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
    runner = {
      pcr4  = "aaaa44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444"
      pcr7  = "aaaa77777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777"
      pcr12 = "aaaacccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
    proxy = {
      pcr4  = "bbbb44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444"
      pcr7  = "bbbb77777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777"
      pcr12 = "bbbbcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
  }
}

run "the_internet_reaches_the_proxy_alone" {
  command = plan

  # The control plane's one ingress rule is from another group, never from an address range.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.controlplane_from_proxy.cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.controlplane_from_proxy.from_port == 8080
    error_message = "the control plane takes something from an address range, or on a port other than 8080"
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.controlplane.from_port == 443 && aws_vpc_security_group_egress_rule.controlplane.to_port == 443 && aws_vpc_security_group_egress_rule.controlplane.ip_protocol == "tcp"
    error_message = "the control plane reaches the internet on something other than 443"
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
    condition     = aws_vpc_security_group_egress_rule.proxy_web.from_port == 443 && aws_vpc_security_group_egress_rule.proxy_web.to_port == 443 && aws_vpc_security_group_egress_rule.proxy_to_controlplane.from_port == 8080
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
    t.block_device_mappings[0].ebs[0].encrypted == "true"])
    error_message = "a disk is not encrypted"
  }
  # The database and the stores are on the control plane's own disk, which is the operator's to
  # size; the proxy holds Caddy and nothing else.
  assert {
    condition     = aws_launch_template.controlplane.block_device_mappings[0].ebs[0].volume_size == var.root_volume_gb && aws_launch_template.proxy.block_device_mappings[0].ebs[0].volume_size == 20
    error_message = "the control plane's disk is not the size asked for"
  }
  # The proxy in subnets of its own, which are what the control plane trusts a browser's
  # address from: a runner or the control plane itself is never among them. Declared in the
  # installation's configuration rather than installed on the machine, so the day this edge
  # changes is an apply.
  assert {
    condition     = length(setintersection(toset(aws_subnet.edge[*].cidr_block), toset(aws_subnet.public[*].cidr_block))) == 0
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

# What a machine's user data is: its role and where the role's document is, as the two systemd
# credentials Spin OS's spin-boot takes - data, which nothing on the machine runs - and nothing
# else. Every step a boot takes is spin-boot's, in Go with tests, in an image whose root nothing
# can write.
run "a_machines_user_data_is_its_role_and_its_document" {
  command = plan

  assert {
    condition = alltrue([for role, u in local.user_data : jsondecode(u) == { "systemd.credentials" = [
      { name = "spin.role", text = role },
      { name = "spin.config", text = "ssm:///spin/spin/${role == "control-plane" ? "controlplane" : role}-config?region=us-east-2" },
    ] }])
    error_message = "a machine's user data is more than its role and its document, as systemd credentials"
  }
  assert {
    condition     = aws_launch_template.controlplane.image_id == "ami-0123456789abcdef0" && aws_launch_template.controlplane.block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "the control plane does not boot the release's image, on its root device"
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

# The installation's secrets are this apply's to write and nobody else's. The first administrator's
# password is ephemeral and written through a write-only attribute, so it is in neither the plan nor
# the state, and written once. The encryption key no apply writes at all: it is agreed with KMS by an
# attested machine, and stored nowhere.
run "the_secrets_are_written_once_and_never_by_a_machine" {
  command = plan

  assert {
    condition = (
      aws_ssm_parameter.admin_password.type == "SecureString" && aws_ssm_parameter.admin_password.value_wo_version == 1 &&
      strcontains(file("${path.module}/secrets.tf"), "ephemeral \"random_password\" \"admin\"") &&
      !strcontains(file("${path.module}/secrets.tf"), "encryption_key")
    )
    error_message = "the administrator's password is in the state or written on every apply, or the encryption key is written by an apply"
  }
  # A plan that would make the key's KMS key or the CA again is refused: a new key is a database
  # nothing opens, a new CA every runner distrusting the control plane. lifecycle is not an
  # attribute a plan can be asked about, so the files are.
  assert {
    condition = (
      length(regexall("prevent_destroy = true", file("${path.module}/secrets.tf"))) == 2 &&
      length(regexall("prevent_destroy = true", file("${path.module}/attested_key.tf"))) == 1
    )
    error_message = "the encryption key's KMS key or the CA can be replaced by an apply"
  }
  # The CA the control plane issues under, and the certificate everything else trusts it by: a CA
  # that can sign, and nothing but the certificate in a document another role reads.
  assert {
    condition = (
      tls_self_signed_cert.ca.is_ca_certificate && contains(tls_self_signed_cert.ca.allowed_uses, "cert_signing") &&
      tls_self_signed_cert.ca.early_renewal_hours == 0 &&
      aws_ssm_parameter.ca.type == "SecureString" &&
      local.controlplane_document.tls.ca_at == "ssm:///spin/spin/controlplane-ca?region=us-east-2" &&
      !strcontains(yamlencode(local.proxy_document), "PRIVATE KEY") && !strcontains(yamlencode(local.runner_document), "PRIVATE KEY")
    )
    error_message = "the CA cannot sign, would be made again by an apply, or its key is in a document another role reads"
  }
  # Named in the control plane's document and read by it; nothing reads them on a machine's behalf.
  # The key is named by its KMS key, never given.
  assert {
    condition = (
      local.controlplane_document.encryption_key_attested.key == aws_kms_key.encryption.arn &&
      local.controlplane_document.bootstrap_admin.password_at == "ssm:///spin/spin/bootstrap-password?region=us-east-2" &&
      local.controlplane_document.bootstrap_admin.email == "admin@example.com" &&
      !contains(keys(local.controlplane_document), "encryption_key") &&
      !contains(keys(local.controlplane_document), "encryption_key_at")
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
# The operator's file is what the installation declares, with what this module knows laid over it:
# its policies as it wrote them, its settings beside the module's own.
run "the_operators_file_is_the_installations" {
  command = plan
  variables {
    installation_config = <<-EOT
      settings:
        default_network_tags: [web]
      network_policies:
        - name: web
          allowPorts: [80, 443]
    EOT
  }

  assert {
    condition = (
      local.installation.network_policies[0].name == "web" &&
      local.installation.network_policies[0].allowPorts == [80, 443] &&
      local.installation.settings.default_network_tags == ["web"] &&
      local.installation.settings.telemetry_collector == "cp.spin.internal:4317" &&
      local.installation.base_domain == "example.com"
    )
    error_message = "the operator's file is not what the installation declares, beside what the module knows"
  }
}

run "the_installation_is_in_its_document_and_not_on_its_machines" {
  command = plan

  assert {
    condition = (
      local.controlplane_document.database == { archive = { bucket = "spin-database-123456789012-us-east-2", region = "us-east-2" } } &&
      local.controlplane_document.production &&
      local.controlplane_document.tls.extra_sans == ["cp.spin.internal"]
    )
    error_message = "the document does not say what the control plane needs before it can read its database"
  }
  assert {
    condition = (
      aws_ssm_parameter.controlplane_config.type == "String" && aws_ssm_parameter.controlplane_config.value == yamlencode(local.controlplane_document) &&
      aws_ssm_parameter.proxy_config.type == "String" && aws_ssm_parameter.proxy_config.value == yamlencode(local.proxy_document) &&
      aws_ssm_parameter.runner_config.type == "String" && aws_ssm_parameter.runner_config.value == yamlencode(local.runner_document)
    )
    error_message = "a document is not what its parameter holds"
  }
  # The installation's own configuration is read by the control plane at every start, which seeds
  # the database from it: nothing applies it by hand on a machine.
  assert {
    condition = (
      local.controlplane_document.installation_at == "ssm:///spin/spin/installation?region=us-east-2" &&
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
      startswith(local.controlplane_document.install.store.principal, "arn:aws:iam::123456789012:role/")
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
      local.installation.host_join.audience == "spin:123456789012:us-east-2:spin" &&
      local.runner_document.install.join.audience == local.installation.host_join.audience &&
      local.installation.host_join.principals == [{ principal = "arn:aws:iam::123456789012:role/spin-us-east-2-runner", shutdown_grace = "100s", preemption_source = "aws" }]
    )
    error_message = "a runner joins for another installation than the one that names its role, or under no policy"
  }
  assert {
    condition = (
      local.controlplane_document.provider == "aws" &&
      local.proxy_document.provider == "aws" && local.runner_document.provider == "aws"
    )
    error_message = "a machine of this installation is not told it runs on AWS"
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
    condition     = toset(keys(aws_route53_record.app)) == toset(["app.${var.domain}", "tunnel.app.${var.domain}", "*.ws.${var.domain}"])
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

# An installation keeps its data past a destroy unless it is being removed: no bucket that holds
# it is emptied by one, and every bucket refuses objects from outside the VPC.
run "a_destroy_keeps_the_data" {
  command = plan

  assert {
    condition = (
      !aws_s3_bucket.volumes.force_destroy && !aws_s3_bucket.database.force_destroy && !aws_s3_bucket.logs.force_destroy &&
      length(aws_s3_bucket_policy.volumes) == 1 && length(aws_s3_bucket_policy.database) == 1 &&
      length(aws_s3_bucket_policy.logs) == 1 && length(aws_s3_bucket_policy.certificates) == 1
    )
    error_message = "a destroy empties a bucket of data, or a bucket answers from outside the VPC"
  }
}

# Removed on purpose, applied first: the buckets lose the policies that refuse the destroy's
# deletes - it runs from outside the VPC, as the root account - and a destroy empties every one.
run "an_installation_being_removed_is_emptied_by_its_destroy" {
  command = plan
  variables {
    decommission = true
  }

  assert {
    condition = (
      aws_s3_bucket.volumes.force_destroy && aws_s3_bucket.database.force_destroy &&
      aws_s3_bucket.logs.force_destroy && aws_s3_bucket.certificates.force_destroy
    )
    error_message = "a bucket stops the destroy of an installation being removed"
  }
  assert {
    condition = (
      length(aws_s3_bucket_policy.volumes) == 0 && length(aws_s3_bucket_policy.database) == 0 &&
      length(aws_s3_bucket_policy.logs) == 0 && length(aws_s3_bucket_policy.certificates) == 0
    )
    error_message = "a bucket still refuses the destroy's deletes from outside the VPC"
  }
}

# An account may hold several installations: of different names in one region, and of one name in
# several regions. IAM is the account's, so what it names carries the region; the regional names
# are under the installation's; and the name is claimed in its region before anything is made
# under it - which holds only while every name is read through the claim, so no file but the
# claim's reads the variable.
run "an_account_holds_several_installations" {
  command = plan

  assert {
    condition = (
      aws_iam_role.controlplane.name == "spin-us-east-2-controlplane" &&
      aws_iam_instance_profile.controlplane.name == "spin-us-east-2-controlplane" &&
      aws_iam_role.proxy.name == "spin-us-east-2-proxy" &&
      aws_iam_instance_profile.proxy.name == "spin-us-east-2-proxy" &&
      aws_iam_role.runner_scope.name == "spin-us-east-2-runner-scope" &&
      aws_iam_role.flow[0].name == "spin-us-east-2-vpc-flow" &&
      aws_iam_policy.boundary.name == "spin-us-east-2-boundary" &&
      aws_iam_policy.session_manager.name == "spin-us-east-2-session-manager" &&
      aws_iam_policy.boot_log.name == "spin-us-east-2-boot-log"
    )
    error_message = "an IAM name does not carry the region, so an installation of this name in another region of the account takes it"
  }
  assert {
    condition = alltrue([for n in [
      aws_ssm_parameter.claim.name, aws_ssm_parameter.ca.name,
      aws_ssm_parameter.admin_password.name, aws_ssm_parameter.controlplane_config.name, aws_ssm_parameter.proxy_config.name,
      aws_ssm_parameter.runner_config.name, aws_ssm_parameter.installation.name,
      aws_cloudwatch_log_group.boot.name, aws_cloudwatch_log_group.flow[0].name,
    ] : startswith(n, "/spin/spin/")])
    error_message = "a parameter or a log group is not under the installation's /spin/<name>/"
  }
  assert {
    condition     = aws_ssm_parameter.claim.name == "/spin/spin/claim" && aws_ssm_parameter.claim.insecure_value == "spin"
    error_message = "the name is not claimed in its region"
  }
  assert {
    condition = alltrue([for f in fileset(path.module, "*.tf") :
    !strcontains(file("${path.module}/${f}"), "var.name") if !contains(["claim.tf", "variables.tf"], f)])
    error_message = "a name is read from the variable and not through the claim: it can be made before the claim refuses the installation"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.proxy.statement : s.sid == "OntoAProxy" &&
    anytrue([for c in s.condition : c.variable == "aws:ResourceTag/spin:installation" && toset(c.values) == toset(["spin"])])])
    error_message = "a proxy may take its address onto another installation's proxy"
  }
}

run "a_name_that_would_make_a_bucket_too_long_is_refused" {
  command = plan
  variables {
    name = "abcdefghijklmnopqrstuvwxyza"
  }
  expect_failures = [var.name]
}

run "a_name_a_bucket_could_not_have_is_refused" {
  command = plan
  variables {
    name = "spin--dev"
  }
  expect_failures = [var.name]
}

run "the_logs_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket.logs.bucket != aws_s3_bucket.volumes.bucket
    error_message = "the logs are kept in the volumes' bucket"
  }
  assert {
    condition     = local.installation.settings.logs_bucket == aws_s3_bucket.logs.bucket
    error_message = "the control plane is not told where its logs go"
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.logs.block_public_acls,
      aws_s3_bucket_public_access_block.logs.block_public_policy,
      aws_s3_bucket_public_access_block.logs.ignore_public_acls,
      aws_s3_bucket_public_access_block.logs.restrict_public_buckets,
    ])
    error_message = "the logs bucket may be made public"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.logs_bucket.statement :
    s.effect == "Deny" && contains(s.actions, "s3:GetObject*") && anytrue([for c in s.condition : c.variable == "aws:SourceVpce"])])
    error_message = "the logs' objects are not refused outside the VPC's endpoint"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.logs_bucket.statement :
    s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport"])])
    error_message = "the logs bucket answers without TLS"
  }
  # A lifecycle deleting under the store would leave its metastore naming splits that are gone.
  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.logs.rule : length(r.expiration) == 0])
    error_message = "a lifecycle rule expires what the store's retention decides"
  }
}

run "the_roles" {
  command = plan

  assert {
    condition = alltrue([for arn in [
      aws_iam_role.controlplane.permissions_boundary, aws_iam_role.runner_scope.permissions_boundary,
      aws_iam_role.proxy.permissions_boundary,
      aws_iam_role.flow[0].permissions_boundary,
    ] : arn == "arn:aws:iam::123456789012:policy/spin-us-east-2-boundary"])
    error_message = "a role carries no boundary"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "iam:PassRole") && contains(s.actions, "iam:Attach*")])
    error_message = "the boundary lets a role write IAM"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "sts:AssumeRole") && s.not_resources == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-runner-scope"])])
    error_message = "the boundary lets a role become another than the runner scope"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "ec2:*SecurityGroup*")])
    error_message = "the boundary lets a role open a security group"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
      s.effect == "Deny" && contains(s.actions, "s3:BypassGovernanceRetention") && contains(s.actions, "s3:PutBucket*") &&
    contains(s.actions, "s3:PutLifecycleConfiguration")])
    error_message = "the control plane can lift the bucket's lock, rewrite its policy or configure it"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane.statement :
      s.effect == "Deny" || length([for a in s.actions : a if a == "s3:*" ||
    (startswith(a, "s3:Put") && !contains(["s3:PutObject", "s3:PutObjectLegalHold"], a))]) == 0])
    error_message = "the control plane is granted all of S3, or a bucket configuration to write"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
    s.effect == "Deny" && contains(s.actions, "s3:PutLifecycleConfiguration")])
    error_message = "a role the boundary bounds can write a bucket's lifecycle"
  }
  assert {
    condition = anytrue([for r in aws_s3_bucket_lifecycle_configuration.volumes.rule :
    r.status == "Enabled" && anytrue([for n in r.noncurrent_version_expiration : n.noncurrent_days > var.object_lock_days])])
    error_message = "the volumes bucket keeps what a delete left forever, or asks to expire it while the lock still holds it"
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

# The workspaces' identity is signed by a key KMS keeps: P-256, made to sign, which the control
# plane may ask to sign digests with ES256 and nothing else may use at all - and its document names
# that key.
run "a_workspaces_identity_is_signed_by_a_key_nothing_takes_out" {
  command = plan

  assert {
    condition     = aws_kms_key.identity.customer_master_key_spec == "ECC_NIST_P256" && aws_kms_key.identity.key_usage == "SIGN_VERIFY"
    error_message = "the identity key is not a P-256 key made to sign"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
      toset(s.actions) == toset(["kms:Sign", "kms:GetPublicKey"]) && s.resources == toset([aws_kms_key.identity.arn]) &&
      anytrue([for c in s.condition : c.variable == "kms:SigningAlgorithm" && toset(c.values) == toset(["ECDSA_SHA_256"])]) &&
    anytrue([for c in s.condition : c.variable == "kms:MessageType" && toset(c.values) == toset(["DIGEST"])])])
    error_message = "the control plane may not sign with the identity key, or may sign more than ES256 digests with it"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane.statement :
    !anytrue([for a in s.actions : startswith(a, "kms:") && !contains(["kms:Sign", "kms:GetPublicKey"], a)])])
    error_message = "the control plane is granted more of KMS than signing"
  }
  assert {
    condition = !anytrue([for s in data.aws_iam_policy_document.proxy.statement :
    anytrue([for a in s.actions : startswith(a, "kms:")])])
    error_message = "the proxy may use a KMS key"
  }
  assert {
    condition     = local.controlplane_document.identity == { key = aws_kms_key.identity.arn }
    error_message = "the control plane's document does not name the identity key"
  }
  # What the key signed is read from CloudTrail and held to the records, which the bucket keeps
  # past its lock.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    toset(s.actions) == toset(["cloudtrail:LookupEvents"])])
    error_message = "the control plane cannot read what the identity key signed"
  }
  assert {
    condition = anytrue([for r in aws_s3_bucket_lifecycle_configuration.volumes.rule :
      r.status == "Enabled" && anytrue([for f in r.filter : f.prefix == "identity/issued/"]) &&
    anytrue([for e in r.expiration : e.days > var.object_lock_days])])
    error_message = "the identity records are never expired, or asked to expire while the lock still holds them"
  }
}

# No machine but the control plane's reads its secrets: Session Manager comes with nothing else
# of SSM, and the boundary refuses the encryption key and the control plane's other secrets to
# any other role, whatever policy it is given later.
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
      contains(s.resources, "arn:aws:ssm:us-east-2:123456789012:parameter/spin/spin/controlplane-ca") &&
      anytrue([for c in s.condition : c.test == "ArnNotEquals" && c.variable == "aws:PrincipalArn" &&
    toset(c.values) == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-controlplane"])])])
    error_message = "a role other than the control plane's can read the CA's key"
  }
  # The first administrator's password and the installation's configuration are the same line as
  # the CA's key: nobody else's to read.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "ssm:GetParameter*") && length(setintersection(s.resources, toset([
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/spin/controlplane-ca",
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/spin/bootstrap-password",
        "arn:aws:ssm:us-east-2:123456789012:parameter/spin/spin/installation",
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

# Every installation has its collector, pinned, and every process pushes to it. Where it sends and
# with what token are the installation's, set in the dashboard: nothing of them is in the plan, the
# documents or a parameter.
run "the_collector" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.collector_from_proxy.from_port == 4317 && aws_vpc_security_group_ingress_rule.collector_from_proxy.cidr_ipv4 == null
    error_message = "the collector's port is open to an address range rather than to the proxy"
  }
  assert {
    condition = (
      # The installation has one, and says nothing of which: that is the image's Alloy.
      local.controlplane_document.install.collector == {} &&
      # Declared in the installation's own configuration, not in what the control plane starts
      # on: an installation is not asked for a collector before it has one.
      local.installation.settings.telemetry_collector == "cp.spin.internal:4317" &&
      local.installation.settings.telemetry_metric_interval == "60s" &&
      !contains(keys(local.controlplane_document), "telemetry")
    )
    error_message = "the collector is pinned here, is told a backend here, or the control plane is not pointed at it"
  }
  assert {
    condition = alltrue([for d in [local.proxy_document, local.runner_document] :
    d.telemetry.enabled && d.telemetry.endpoint == "cp.spin.internal:4317" && d.telemetry.metric_interval == "60s"])
    error_message = "the proxy or the runners are not pointed at the collector"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane.statement :
      s.sid != "ItsDocumentAndSecrets" || length(s.resources) == 4
    ])
    error_message = "the control plane reads a telemetry token from SSM: it is the database's"
  }
}

# The database is on the control plane's machine, and outlives it through its archive: a bucket of
# its own, versioned, which the control plane's role alone reaches - the volumes' bucket, whose
# credentials hosts hold, never.
run "the_databases_archive" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket.database.bucket == "spin-database-123456789012-us-east-2" &&
      aws_s3_bucket.database.bucket != aws_s3_bucket.volumes.bucket &&
      aws_s3_bucket.database.bucket != aws_s3_bucket.logs.bucket &&
      local.controlplane_document.database.archive.bucket == aws_s3_bucket.database.bucket &&
      local.controlplane_document.database.archive.region == "us-east-2" &&
      !contains(keys(local.controlplane_document.database.archive), "endpoint")
    )
    error_message = "the control plane is not told where its database's archive is, or it is another bucket's"
  }
  assert {
    condition = (
      aws_s3_bucket_versioning.database.versioning_configuration[0].status == "Enabled" &&
      aws_s3_bucket.database.force_destroy != true &&
      anytrue([for r in aws_s3_bucket_lifecycle_configuration.database.rule : r.status == "Enabled" &&
      anytrue([for n in r.noncurrent_version_expiration : n.noncurrent_days == 15])]) &&
      anytrue([for r in aws_s3_bucket_lifecycle_configuration.database.rule : r.status == "Enabled" &&
      length(r.abort_incomplete_multipart_upload) > 0])
    )
    error_message = "a delete in the archive cannot be undone, a destroy empties it, or what it replaced is kept for ever"
  }
  # spin opens no store that is not versioned under a lock with a default retention; the lifecycle
  # asks for a replaced version only once the lock has let it go.
  assert {
    condition = (
      aws_s3_bucket.database.object_lock_enabled &&
      aws_s3_bucket_object_lock_configuration.database.rule[0].default_retention[0].mode == "GOVERNANCE" &&
      aws_s3_bucket_object_lock_configuration.database.rule[0].default_retention[0].days == 14 &&
      alltrue([for r in aws_s3_bucket_lifecycle_configuration.database.rule : alltrue([for n in r.noncurrent_version_expiration :
      n.noncurrent_days > aws_s3_bucket_object_lock_configuration.database.rule[0].default_retention[0].days])])
    )
    error_message = "the archive is not under a GOVERNANCE lock of two weeks, or its lifecycle expires what the lock still holds"
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.database.block_public_acls,
      aws_s3_bucket_public_access_block.database.block_public_policy,
      aws_s3_bucket_public_access_block.database.ignore_public_acls,
      aws_s3_bucket_public_access_block.database.restrict_public_buckets,
      aws_s3_bucket_ownership_controls.database.rule[0].object_ownership == "BucketOwnerEnforced",
    ])
    error_message = "the archive may be made public, or hold an object its account does not own"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.database_bucket.statement :
      s.effect == "Deny" && contains(s.actions, "s3:GetObject*") && anytrue([for c in s.condition : c.variable == "aws:SourceVpce"])]) && anytrue([for s in data.aws_iam_policy_document.database_bucket.statement :
    s.effect == "Deny" && anytrue([for c in s.condition : c.variable == "aws:SecureTransport"])])
    error_message = "the archive's objects are reached from outside the VPC's endpoint, or without TLS"
  }
  # The control plane reads, writes and deletes what it ships, lists it, and reads its versioning
  # and its lock; no version of it, and nothing of its configuration to write.
  assert {
    condition = toset(flatten([for s in data.aws_iam_policy_document.controlplane.statement : s.actions if s.effect != "Deny" && anytrue([for r in s.resources : startswith(r, "arn:aws:s3:::spin-database-")])])) == toset([
      "s3:ListBucket", "s3:GetBucketVersioning", "s3:GetBucketObjectLockConfiguration",
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
    ])
    error_message = "the control plane is given more or less of its database's archive than spin opens it with and ships to it"
  }
  # Whatever any other role is given later, the boundary refuses it the archive; and no role
  # erases a version of it.
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "s3:*") &&
      s.resources == toset(["arn:aws:s3:::spin-database-123456789012-us-east-2", "arn:aws:s3:::spin-database-123456789012-us-east-2/*"]) &&
      anytrue([for c in s.condition : c.test == "ArnNotEquals" && c.variable == "aws:PrincipalArn" &&
    toset(c.values) == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-controlplane"])])])
    error_message = "a role other than the control plane's can reach the database's archive"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.boundary.statement :
      s.effect == "Deny" && contains(s.actions, "s3:DeleteObjectVersion") && length(s.condition) == 0 &&
    contains(s.resources, "arn:aws:s3:::spin-database-123456789012-us-east-2/*")])
    error_message = "a role can erase a version of the database's archive"
  }
  assert {
    condition = !anytrue([for d in [data.aws_iam_policy_document.proxy, data.aws_iam_policy_document.runner_scope] :
    anytrue([for s in d.statement : anytrue([for r in s.resources : startswith(r, "arn:aws:s3:::spin-database-")])])])
    error_message = "the proxy's role or the runners' credential is given the database's archive"
  }
}

# Every machine boots its role's image of the release: Spin OS, into which spin-boot laid that
# role's part of what the release's workflow signed, checked against its signature, whose root the
# kernel checks every block of, and which its role's Secure Boot key signed. Which image that is,
# role by role and region by region, is images.json: ids this commit names, so an image published
# again reaches an installation by its module's ref moving and by nothing else.
run "the_machines_boot_their_roles_image_of_the_release" {
  command = plan
  variables {
    spin_version = "v20260928.02"
    image_ids    = {}
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-west-2", name = "us-west-2" }
  }

  assert {
    # Whatever ids images.json holds for it - a pull request that publishes the release again
    # changes those, and nothing here should have to follow.
    condition = alltrue([for role in ["control-plane", "runner", "proxy"] :
      anytrue([for f in data.aws_ami.spin_os[role].filter : f.name == "image-id" && f.values == toset([jsondecode(file("${path.module}/../../images.json"))["v20260928.02"][role]["us-west-2"]])])
    ])
    error_message = "an image is not the one images.json names for its role of the release in its region"
  }
  assert {
    condition     = aws_launch_template.controlplane.image_id == local.image["control-plane"] && aws_launch_template.proxy.image_id == local.image["proxy"]
    error_message = "a machine boots another image than its role's of the release"
  }
  assert {
    condition     = output.images["runner"].id == local.image["runner"] && output.images["runner"].root_device == "/dev/xvda"
    error_message = "the runners are not handed the runner's image of the release and its root device"
  }
}

# A release with no image in the region is refused at plan, naming where it has one.
run "a_release_with_no_image_here_is_refused" {
  command = plan
  variables {
    # images.json has it in us-west-2; the tests' region is us-east-2.
    spin_version = "v20260928.02"
    image_ids    = {}
  }
  expect_failures = [data.aws_ami.spin_os]
}

# Images of your own are three, one per role, or none: one image for every machine would boot a
# runner under the control plane's Secure Boot key.
run "images_of_your_own_are_one_per_role" {
  command = plan
  variables {
    image_ids = { "control-plane" = "ami-0123456789abcdef0" }
  }
  expect_failures = [var.image_ids]
}

# The control plane's key is answered to nothing but an attested control plane: the KMS key agrees
# keys and does nothing else, the only statement that lets anything ask is the control plane's role
# with this image's PCRs, the account keeps the key without using it, and whatever a later edit
# allows is refused without an attestation document.
run "the_key_is_answered_only_to_an_attested_control_plane" {
  command = plan

  override_resource {
    target = aws_iam_role.controlplane
    values = { arn = "arn:aws:iam::123456789012:role/spin-us-east-2-controlplane" }
  }

  assert {
    condition     = aws_kms_key.encryption.customer_master_key_spec == "ECC_NIST_P256" && aws_kms_key.encryption.key_usage == "KEY_AGREEMENT"
    error_message = "the encryption key's KMS key is not a P-256 key-agreement key"
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.encryption_key.statement :
      s.effect == "Deny" || (!contains(s.actions, "kms:DeriveSharedSecret") && !contains(s.actions, "kms:*")) || (
        toset(s.actions) == toset(["kms:DeriveSharedSecret"]) &&
        alltrue([for p in s.principals : toset(p.identifiers) == toset(["arn:aws:iam::123456789012:role/spin-us-east-2-controlplane"])]) &&
        anytrue([for c in s.condition : c.variable == "kms:RecipientAttestation:NitroTPMPCR4" && toset(c.values) == toset([var.image_measurements["control-plane"].pcr4])]) &&
        anytrue([for c in s.condition : c.variable == "kms:RecipientAttestation:NitroTPMPCR7" && toset(c.values) == toset([var.image_measurements["control-plane"].pcr7])]) &&
        anytrue([for c in s.condition : c.variable == "kms:RecipientAttestation:NitroTPMPCR12" && toset(c.values) == toset([var.image_measurements["control-plane"].pcr12])]) &&
        anytrue([for c in s.condition : c.variable == "kms:KeyAgreementAlgorithm" && toset(c.values) == toset(["ECDH"])])
      )
    ])
    error_message = "something other than the control plane's role, with this image's PCRs, may agree the key"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.encryption_key.statement :
      s.effect == "Deny" && toset(s.actions) == toset(["kms:DeriveSharedSecret"]) &&
      anytrue([for p in s.principals : contains(p.identifiers, "*")]) &&
    anytrue([for c in s.condition : c.test == "Null" && toset(c.values) == toset(["true"]) && startswith(c.variable, "kms:RecipientAttestation:NitroTPMPCR")])])
    error_message = "the key can be agreed without an attestation document if a later edit of its policy allows it"
  }
  assert {
    condition     = strcontains(file("${path.module}/attested_key.tf"), "prevent_destroy = true")
    error_message = "the encryption key's KMS key can be destroyed by a plan, and with it the installation"
  }
}

# The control plane is told the runner's build a host may join as - this release's, never the
# control plane's own - and nothing else.
run "a_host_joins_only_as_the_runners_build" {
  command = plan

  assert {
    condition     = yamldecode(aws_ssm_parameter.controlplane_config.value).host_attestation.runner == [var.image_measurements["runner"]]
    error_message = "the control plane is told other builds than the runner's a host may join as"
  }
}

# The control plane is told the proxy's role and build, which the proxy proves for its token - its
# own role and image, never a runner's - and the proxy is told whom it proves it to.
run "the_proxy_proves_it_is_the_proxys_build" {
  command = plan

  assert {
    condition = yamldecode(aws_ssm_parameter.controlplane_config.value).host_attestation.proxy == {
      principal = "arn:aws:iam::123456789012:role/spin-us-east-2-proxy"
      builds    = [var.image_measurements["proxy"]]
    }
    error_message = "the control plane is told another role or build than the proxy's for the proxy's token"
  }
  assert {
    condition     = yamldecode(aws_ssm_parameter.proxy_config.value).install.join == { audience = local.join_audience }
    error_message = "the proxy is not told the installation it proves it is the proxy to"
  }
}

# A release whose runner's image has no measurements, with none given, is refused at plan: no host
# of it could join.
run "a_release_with_no_runner_measurements_is_refused" {
  command = plan
  variables {
    image_measurements = null
  }
  expect_failures = [data.aws_ami.spin_os, aws_kms_key.encryption]
}

# A release published before its PCRs were, with none given, is refused at plan: a machine of it
# could not attest, and its control plane would come up with no key.
run "a_release_with_no_measurements_is_refused" {
  command = plan
  variables {
    spin_version       = "v20260928.02"
    image_ids          = {}
    image_measurements = null
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-west-2", name = "us-west-2" }
  }
  expect_failures = [aws_kms_key.encryption, data.aws_ami.spin_os]
}

# What the ami repository's pull request writes beside the images is what the key policy reads: a
# dated release, a role, and three SHA384 digests.
run "measurements_json_is_releases_roles_and_their_pcrs" {
  command = plan

  assert {
    condition = alltrue([for release, roles in local.measurements :
      can(regex("^v[0-9]{8}\\.[0-9]+$", release)) && length(roles) > 0 && alltrue([for role, pcrs in roles :
        contains(local.roles, role) && keys(pcrs) == tolist(["pcr12", "pcr4", "pcr7"]) &&
        alltrue([for pcr in values(pcrs) : can(regex("^[0-9a-f]{96}$", pcr))])
      ])
    ])
    error_message = "measurements.json is not { release: { role: { pcr4, pcr7, pcr12 } } } of SHA384 digests"
  }
}

# What the ami repository's pull request writes is what this module reads: a dated release, each of
# the three roles, a region, an AMI id.
run "images_json_is_releases_roles_regions_and_amis" {
  command = plan

  assert {
    condition = length(local.images) > 0 && alltrue([for release, roles in local.images :
      can(regex("^v[0-9]{8}\\.[0-9]+$", release)) && toset(keys(roles)) == toset(local.roles) &&
      alltrue([for role, regions in roles : length(regions) > 0 && alltrue([for region, ami in regions :
    can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", region)) && can(regex("^ami-[0-9a-f]{17}$", ami))])])])
    error_message = "images.json is not { <release>: { <role>: { <region>: <ami-id> } } } with every role"
  }
}

# Every ARN is of the provider's partition, so the module runs in GovCloud and China as it does
# in aws.
run "the_arns_are_the_partitions" {
  command = plan
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws-us-gov" }
  }

  assert {
    condition = (
      local.controlplane_role_arn == "arn:aws-us-gov:iam::123456789012:role/spin-us-east-2-controlplane" &&
      anytrue([for s in data.aws_iam_policy_document.controlplane.statement : s.sid == "SizeTheRunners" &&
      alltrue([for r in s.resources : startswith(r, "arn:aws-us-gov:autoscaling:")])]) &&
      anytrue([for s in data.aws_iam_policy_document.boundary.statement : s.sid == "OnlyTheProxysAddress" &&
      alltrue([for r in s.not_resources : startswith(r, "arn:aws-us-gov:ec2:")])])
    )
    error_message = "an ARN this module spells is of another partition than the provider's"
  }
  # An ARN spelled with the partition written out is one the assertion above misses until it is
  # among those it names; none is.
  assert {
    condition     = alltrue([for f in fileset(path.module, "*.tf") : !strcontains(file("${path.module}/${f}"), "\"arn:aws:")])
    error_message = "a file spells an ARN in the aws partition: it is local.arn"
  }
}

# A Local Zone or a Wavelength Zone the account opted into is not one the installation's subnets go in.
run "the_subnets_are_in_the_regions_own_zones" {
  command = plan

  assert {
    condition     = anytrue([for f in data.aws_availability_zones.available.filter : f.name == "opt-in-status" && f.values == toset(["opt-in-not-required"])])
    error_message = "a subnet may be made in a zone the account opted into, where none of the machines exist"
  }
}

run "a_vpc_range_the_subnets_do_not_fit_is_refused" {
  command = plan
  variables {
    vpc_cidr = "10.42.0.0/20"
  }
  expect_failures = [var.vpc_cidr]
}

run "the_logs" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc[0].traffic_type == "ALL" && aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "the flow log is not every connection, or is kept for ever"
  }
}

# The bill is read and never written: the control plane may ask what the installation cost and is
# forecast to, and see its budget, and nothing more of Cost Explorer or Budgets. The budget is over
# the installation's own tag, and tells who it names past 80 % and 100 %, and when 100 % is
# forecast.
run "the_bill_is_read_and_never_written" {
  command = plan
  variables {
    monthly_budget_usd = 500
    budget_emails      = ["ops@example.com"]
  }

  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controlplane.statement : alltrue([for a in s.actions :
      (!startswith(a, "ce:") || contains(["ce:GetCostAndUsage", "ce:GetCostForecast"], a)) &&
    (!startswith(a, "budgets:") || a == "budgets:ViewBudget")])])
    error_message = "the control plane may change the bill's budgets or cost categories, not only read them"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    contains(s.actions, "ce:GetCostAndUsage") && contains(s.actions, "ce:GetCostForecast")])
    error_message = "the control plane cannot read the bill"
  }
  assert {
    condition = anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    contains(s.actions, "budgets:ViewBudget")])
    error_message = "the control plane cannot see the installation's budget"
  }
  assert {
    condition = (aws_budgets_budget.monthly[0].limit_amount == "500" && aws_budgets_budget.monthly[0].time_unit == "MONTHLY" &&
    alltrue([for f in aws_budgets_budget.monthly[0].cost_filter : f.name == "TagKeyValue" && alltrue([for v in f.values : startswith(v, "user:spin:installation$")])]))
    error_message = "the budget is not the month's, of the installation's own tag"
  }
  assert {
    condition = (toset([for n in aws_budgets_budget.monthly[0].notification : "${n.notification_type}:${n.threshold}"]) == toset(["ACTUAL:80", "ACTUAL:100", "FORECASTED:100"]) &&
    alltrue([for n in aws_budgets_budget.monthly[0].notification : n.subscriber_email_addresses == toset(["ops@example.com"])]))
    error_message = "the budget does not tell who it names at 80 % and 100 %, and when 100 % is forecast"
  }
}

# The bill's S3 is told apart by bucket: the disks' is shared out to each volume by its bytes, and
# the rest is the platform's. A bucket with no role, or the volumes' role on another, would put
# one's cost on the other.
run "every_bucket_is_billed_by_its_role" {
  command = plan

  assert {
    condition = (aws_s3_bucket.volumes.tags["spin:role"] == "volumes" &&
      aws_s3_bucket.database.tags["spin:role"] == "database" &&
      aws_s3_bucket.logs.tags["spin:role"] == "logs" &&
    aws_s3_bucket.certificates.tags["spin:role"] == "certificates")
    error_message = "a bucket is not tagged with its role, and its cost is not told apart"
  }
}

run "the_control_plane_is_told_its_scope_and_its_budget" {
  command = plan
  variables {
    monthly_budget_usd = 500
  }

  assert {
    condition     = local.installation.settings.bill_scope == local.name
    error_message = "the control plane reads the bill of something other than what carries its own tag"
  }
  assert {
    condition     = local.installation.settings.bill_budget == "arn:aws:budgets::123456789012:budget/${local.name}-monthly" && aws_budgets_budget.monthly[0].name == "${local.name}-monthly"
    error_message = "the control plane is told a budget other than the installation's"
  }
}

run "no_budget_unless_one_is_named" {
  command = plan

  assert {
    condition     = !contains(keys(local.installation.settings), "bill_budget")
    error_message = "the control plane is told of a budget nobody named"
  }

  assert {
    condition     = length(aws_budgets_budget.monthly) == 0
    error_message = "a budget was made where none was named"
  }
  assert {
    condition = !anytrue([for s in data.aws_iam_policy_document.controlplane.statement :
    contains(s.actions, "budgets:ViewBudget")])
    error_message = "the control plane is let see a budget that does not exist"
  }
}
