# What each machine starts on: one document per role, an object in its own bucket
# (documents_bucket.tf), written by this apply and read by that role's machines (spin's
# internal/bootstrap). A machine is told its role and where its document is and nothing else - its
# user data is those two, as systemd credentials (user_data below) - and the image's spin-boot does
# the rest from what the document says.
#
# Beside the documents, the installation's own configuration (installation.yaml, as it would be
# kept in git): where the installation starts, which an administrator changes from the dashboard
# once the database is open. The control plane seeds its database from it when it starts, before
# it serves; a later change to it is an apply and the next start, and reaches the installation as
# a change for an administrator to apply or dismiss - never written over what they decided.
#
# A document holds no secret. Where one is, it says where (secrets.tf): the key, the CA's key and
# the first administrator's password are parameters of their own, and only the control plane's
# role reads them.

locals {
  installation_parameter = "/spin/${local.name}/installation"

  # Each role's document, by its bucket's name rather than the bucket's attributes: known at plan,
  # as the user data that names it and the policies that grant it are. "docs" and not "documents":
  # the longest name a bucket of this installation may have is "<name>-database-...".
  documents_bucket = "${local.name}-docs-${local.account}-${local.region}"
  document_key     = { for role in ["control-plane", "proxy", "runner"] : role => "${role}.yaml" }
  document_arn     = { for role, key in local.document_key : role => "${local.arn}:s3:::${local.documents_bucket}/${key}" }

  # A document and a parameter, as spin reads one: with its region, which a machine's SDK does not
  # otherwise know.
  document_at = { for role, key in local.document_key : role => "s3://${local.documents_bucket}/${key}?region=${local.region}" }
  ssm = { for k, p in {
    installation   = local.installation_parameter
    ca             = local.ca_parameter
    admin_password = local.admin_password_parameter
  } : k => "ssm://${p}?region=${local.region}" }

  # How long a booting machine may go without saying it is still going before its group abandons
  # it, and how often it says so: the beats are what let a first boot take half an hour.
  heartbeat         = "60s"
  heartbeat_timeout = 300

  # Which installation a runner's signed request is for (spin's internal/domain/hostjoin): the
  # account, the region and the name, so a request signed for another installation - one of the
  # same name in another region too - is not one this takes.
  join_audience = "spin:${local.account}:${local.region}:${local.name}"

  telemetry_of = {
    enabled         = true
    endpoint        = local.collector
    metric_interval = local.metric_interval
  }

  controlplane_document = {
    # The platform (spin's internal/provider): hosts join by who they are, with their IAM role.
    provider = "aws"
    # The database is on this machine; what outlives the machine is its archive, which the
    # database cannot name for itself. No endpoint: AWS's S3, through the VPC's endpoint.
    database = {
      archive = {
        bucket = aws_s3_bucket.database.bucket
        region = local.region
      }
      # Who holds the database and the requests for it, in a bucket that keeps no versions
      # (database_bucket.tf).
      handover = {
        bucket = aws_s3_bucket.database_handover.bucket
        region = local.region
      }
    }
    # Agreed with KMS at every start by a machine whose NitroTPM proves this release's image
    # (attested_key.tf): named here, held nowhere.
    encryption_key_attested = { key = aws_kms_key.encryption.arn }
    # The names its certificate must cover, and the CA it issues it under.
    tls = { extra_sans = [local.cp_host], ca_at = local.ssm.ca }
    # The identity key is KMS's, made unseen and granted under the identity-keys role, and opened
    # only by an attested runner, which signs its workspaces' identities (identity.tf).
    identity = { key = aws_kms_key.identity.arn, role = aws_iam_role.identity_keys.arn }
    # Every volume's key is KMS's, granted under the volume-keys role and opened only by an
    # attested runner (volume_keys.tf).
    volume_keys     = { key = aws_kms_key.volumes.arn, role = aws_iam_role.volume_keys.arn }
    production      = true
    installation_at = local.ssm.installation
    bootstrap_admin = { email = local.admin_email, password_at = local.ssm.admin_password }
    # The builds of the runner's image a host may join as, and of the proxy's the proxy is given
    # its token as - with the proxy's role - by what each NitroTPM measures: this release's not
    # revoked, as measurements.json has them (attested_key.tf). A machine of any other is given
    # nothing. The runner's and the control plane's carry what their release signed of them, which
    # each records its key as a writer of volumes with.
    host_attestation = {
      runner        = local.signed_of["runner"]
      proxy         = { principal = local.proxy_role_arn, builds = local.pcrs_of["proxy"] }
      control_plane = local.signed_of["control-plane"]
    }

    # What the machine's first boot does, and what the control plane never reads.
    install = {
      release = var.spin_version
      log     = local.boot_log
      store = {
        bucket    = aws_s3_bucket.volumes.bucket
        region    = local.region
        principal = aws_iam_role.runner_scope.arn
      }
      launch = {
        aws = {
          region    = local.region
          group     = local.controlplane_group
          hook      = "ready"
          heartbeat = local.heartbeat
          zone      = aws_route53_zone.internal.zone_id
          name      = local.cp_host
          ttl       = local.internal_record_ttl
        }
      }
      # The collector, which is the image's Alloy: where it sends is the installation's, set in the
      # dashboard (telemetry.tf).
      collector = {}
    }
  }

  proxy_document = {
    provider      = local.controlplane_document.provider
    control_plane = local.url
    ca_cert       = tls_self_signed_cert.ca.cert_pem
    domain        = var.domain
    acme_email    = var.acme_email
    telemetry     = local.telemetry_of
    install = {
      release = var.spin_version
      log     = local.boot_log
      launch = {
        aws = {
          region       = local.region
          group        = local.proxy_group
          hook         = "ready"
          heartbeat    = local.heartbeat
          zone         = aws_route53_zone.internal.zone_id
          name         = local.proxy_host
          ttl          = local.internal_record_ttl
          elastic_ip   = aws_eip.proxy.allocation_id
          certificates = aws_s3_bucket.certificates.bucket
          # Where the identity key is kept, whose first version the proxy publishes as id.<domain>.
          issuer = aws_s3_bucket.volumes.bucket
        }
      }
      # Who the proxy proves it is to, for its token: the installation hosts join.
      join = { audience = local.join_audience }
    }
  }

  # A runner's release is not here: it is the control plane's, asked of it once the runner has
  # joined, because the control plane an update is replacing may be either release for a while.
  runner_document = {
    provider      = local.controlplane_document.provider
    control_plane = local.url
    ca_cert       = tls_self_signed_cert.ca.cert_pem
    # The relay by the proxy's private name: its public address would take the relay out through
    # the internet gateway and back in. The certificate is checked as the relay's own name.
    relay_dial = "${local.proxy_host}:443"
    telemetry  = local.telemetry_of
    install = {
      log    = local.boot_log
      launch = { aws = { region = local.region } }
      join   = { audience = local.join_audience }
    }
  }

  # The operator's config file, with what this module knows about the installation added.
  # Decoded whole, "{}" for none: a conditional between an empty object and the file's would have
  # to give both one type, which a file with anything in it never has.
  operator = yamldecode(var.installation_config == "" ? "{}" : var.installation_config)
  installation = merge(local.operator, {
    base_domain = var.domain
    # Who joins as a host: the runners' role, under the policy a runner of it starts with.
    host_join = {
      audience   = local.join_audience
      principals = [merge({ principal = local.runner_role_arn }, var.runner_policy)]
    }
    settings = merge(try(local.operator.settings, {}), merge({
      # Whose word about a browser's address the control plane takes: the proxy's subnets, where
      # nothing but a proxy runs.
      trusted_proxies = aws_subnet.edge[*].cidr_block
      # What the control plane makes the runners' groups from, one per host class, as spin's AWS
      # provider reads it (awscp.Fleet): the template by its name, which the runners module gives
      # it, and where and how its machines start. Never an image: what a machine boots is the
      # template's, which only this apply writes.
      autoscaling_fleet = jsonencode({
        region          = local.region
        name            = local.name
        launch_template = local.runner_template
        subnets         = aws_subnet.public[*].id
        drain_seconds   = var.runner_drain_seconds
        # The data goes on the instance store unless the template gives it a volume of its own,
        # and a .metal type has KVM by being metal and refuses nested virtualization.
        local_storage = var.runner_data_volume_gb > 0 ? "included" : "required"
        bare_metal    = var.runner_nested_virtualization ? "excluded" : "required"
        rolling       = var.runner_rollout == "rolling"
        tags          = local.tags
      })
      # The most runners of every kind together, which the dashboard may lower or raise.
      autoscaling_max_hosts    = var.max_runners
      autoscaling_idle_minutes = var.runner_idle_minutes
      }, var.quiet_hours == "" ? {} : {
      autoscaling_quiet_hours = var.quiet_hours
      autoscaling_time_zone   = var.time_zone
      }, {
      # The role a team's secret kept in Secrets Manager is read under (team_secrets.tf).
      team_secrets_role = local.team_secrets_role_arn
      # Where the installation pushes what it records: the collector on the control plane's
      # own machine.
      telemetry_collector       = local.collector
      telemetry_metric_interval = local.metric_interval
      # Where it keeps its logs and traces; how long, the operator's file says.
      # Its name and not its id: the name is known at plan, and what a machine starts on is
      # hashed into its launch template then.
      logs_bucket = aws_s3_bucket.logs.bucket
      # Which of the account's costs are this installation's - what carries its spin:installation
      # tag - for the control plane's reading of the bill (iam.tf, ReadTheBill).
      bill_scope = local.name
      }, var.monthly_budget_usd == null ? {} : {
      # Its budget (budget.tf), by an ARN known at plan rather than read off the budget.
      bill_budget = "${local.arn}:budgets::${local.account}:budget/${local.name}-monthly"
    }))
    # The default kind of runner, from this module's runner_* variables, beside the operator's
    # own: each seeded once, and the dashboard's to change after (spin's hostclass).
    host_classes = concat([{
      name           = "default"
      description    = "The runners this installation was made with."
      instance_types = var.runner_instance_types
      vcpus          = var.runner_vcpus
      spot           = var.runner_spot
      }], [
      for c in try(local.operator.host_classes, []) : c if c.name != "default"
    ])
  })
}

resource "aws_s3_object" "document" {
  for_each = {
    "control-plane" = local.controlplane_document
    proxy           = local.proxy_document
    runner          = local.runner_document
  }
  bucket       = aws_s3_bucket.documents.id
  key          = local.document_key[each.key]
  content      = yamlencode(each.value)
  content_type = "application/yaml"
  tags         = local.tags
  # Written once the bucket refuses what is not TLS and holds every version an apply replaces.
  depends_on = [aws_s3_bucket_policy.documents, aws_s3_bucket_versioning.documents]
}

# The operator's file may say whom the installation registers, so it is the control plane's
# alone to read; and it grows, so it is not held to a standard parameter's 4 KiB.
resource "aws_ssm_parameter" "installation" {
  name        = local.installation_parameter
  description = "${local.name}'s configuration, which its control plane seeds its database from"
  type        = "SecureString"
  tier        = "Intelligent-Tiering"
  value       = yamlencode(local.installation)
  tags        = local.tags
}

# Every machine's user data: which role it is and where that role's document is, as the two
# systemd credentials Spin OS's spin-boot unit takes. systemd-imds imports them from IMDS into
# /run/credstore; nothing on the machine runs the user data.
locals {
  user_data = { for role, doc in local.document_at :
    role => jsonencode({ "systemd.credentials" = [
      { name = "spin.role", text = role },
      { name = "spin.config", text = doc },
    ] })
  }
}
