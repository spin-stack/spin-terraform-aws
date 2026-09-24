# What each machine starts on: one document per role in the parameter store, written by this
# apply and read by that role's machines (spin's internal/bootstrap). A machine is told where its
# document is and nothing else - its user data is the same five lines for every role
# (files/boot.sh.tftpl) - and spin-boot does the rest from what the document says.
#
# Beside the documents, the installation's own configuration (installation.yaml, as it would be
# kept in git): what an administrator could change once the catalog is open. The control plane
# makes its catalog match it every time it starts, before it serves, so a change to it is an
# apply and the next start of a control plane - not a command somebody runs on a machine.
#
# A document holds no secret. Where one is, it says where (secrets.tf): the key, the CA's key,
# the first administrator's password and the collector's token are parameters of their own, and
# only the control plane's role reads them.

locals {
  config_parameter       = "/${var.name}/controlplane-config"
  proxy_parameter        = "/${var.name}/proxy-config"
  runner_parameter       = "/${var.name}/runner-config"
  installation_parameter = "/${var.name}/installation"

  # A parameter, as spin reads one: with its region, which a machine's SDK does not otherwise
  # know.
  ssm = { for k, p in {
    config         = local.config_parameter
    proxy          = local.proxy_parameter
    runner         = local.runner_parameter
    installation   = local.installation_parameter
    key            = local.key_parameter
    ca             = local.ca_parameter
    admin_password = local.admin_password_parameter
    grafana_token  = local.token_parameter_grafana
  } : k => "ssm://${p}?region=${local.region}" }

  # How long a booting machine may go without saying it is still going before its group abandons
  # it, and how often it says so: the beats are what let a first boot take half an hour.
  heartbeat         = "60s"
  heartbeat_timeout = 300

  # Which installation a runner's signed request is for (spin's internal/domain/hostjoin): the
  # account and the name, so a request signed for another installation is not one this takes.
  join_audience = "spin:${local.account}:${var.name}"

  telemetry_of = {
    enabled         = local.telemetry
    endpoint        = local.collector
    metric_interval = local.metric_interval
  }

  controlplane_document = {
    # The platform (spin's internal/provider): hosts join by who they are, with their IAM role.
    provider = "aws"
    database = {
      url = local.database_url
      # An RDS token signed per connection by this machine's role: the catalog has no password
      # to keep anywhere.
      auth = "aws-iam"
    }
    encryption_key_at = local.ssm.key
    # The names its certificate must cover, and the CA it issues it under.
    tls             = { extra_sans = [local.cp_host], ca_at = local.ssm.ca }
    production      = true
    installation_at = local.ssm.installation
    bootstrap_admin = { email = local.admin_email, password_at = local.ssm.admin_password }

    # What the machine's first boot does, and what the control plane never reads.
    install = {
      release = var.spin_version
      log     = local.boot_log
      store = {
        bucket   = aws_s3_bucket.volumes.bucket
        region   = local.region
        role_arn = aws_iam_role.runner_scope.arn
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
      # The role the control plane signs in as, made by RDS's master user, whose password RDS
      # keeps in Secrets Manager: read once by the first boot, never by the control plane.
      catalog = {
        admin_user   = aws_db_instance.catalog.username
        admin_secret = aws_db_instance.catalog.master_user_secret[0].secret_arn
      }
      collector = !local.telemetry ? null : {
        otlp_endpoint = var.grafana_cloud.otlp_endpoint
        instance_id   = var.grafana_cloud.instance_id
        token_at      = local.ssm.grafana_token
        log_severity  = var.grafana_cloud.log_severity
        alloy         = { version = var.grafana_cloud.alloy_version, sha256 = var.grafana_cloud.alloy_sha256 }
      }
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
        }
      }
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
  operator = var.installation_config == "" ? {} : yamldecode(var.installation_config)
  installation = merge(local.operator, {
    base_domain = var.domain
    # Who joins as a host: the runners' role, under the policy a runner of it starts with.
    host_join = {
      audience = local.join_audience
      aws      = [merge({ role = local.runner_role_arn }, var.runner_policy)]
    }
    settings = merge(try(local.operator.settings, {}), merge({
      # Whose word about a browser's address the control plane takes: the proxy's subnets, where
      # nothing but a proxy runs.
      trusted_proxies          = aws_subnet.edge[*].cidr_block
      autoscaling_group        = local.runner_group
      autoscaling_region       = local.region
      autoscaling_idle_minutes = var.runner_idle_minutes
      }, var.quiet_hours == "" ? {} : {
      autoscaling_quiet_hours = var.quiet_hours
      autoscaling_time_zone   = var.time_zone
      }, !local.telemetry ? {} : {
      # Where the installation pushes what it records: the collector on the control plane's
      # own machine.
      telemetry_collector       = local.collector
      telemetry_metric_interval = local.metric_interval
    }))
  })
}

resource "aws_ssm_parameter" "controlplane_config" {
  name        = local.config_parameter
  description = "What ${var.name}'s control plane machines start on"
  type        = "String"
  value       = yamlencode(local.controlplane_document)
  tags        = local.tags
}

resource "aws_ssm_parameter" "proxy_config" {
  name        = local.proxy_parameter
  description = "What ${var.name}'s proxy machines start on"
  type        = "String"
  value       = yamlencode(local.proxy_document)
  tags        = local.tags
}

resource "aws_ssm_parameter" "runner_config" {
  name        = local.runner_parameter
  description = "What ${var.name}'s runners start on"
  type        = "String"
  value       = yamlencode(local.runner_document)
  tags        = local.tags
}

# The operator's file may say whom the installation registers, so it is the control plane's
# alone to read; and it grows, so it is not held to a standard parameter's 4 KiB.
resource "aws_ssm_parameter" "installation" {
  name        = local.installation_parameter
  description = "${var.name}'s configuration, which its control plane makes its catalog match at every start"
  type        = "SecureString"
  tier        = "Intelligent-Tiering"
  value       = yamlencode(local.installation)
  tags        = local.tags
}

# The same five lines for every machine, told which role it is and where that role's document is.
locals {
  user_data = { for role, doc in { "control-plane" = local.ssm.config, proxy = local.ssm.proxy, runner = local.ssm.runner } :
    role => templatefile("${path.module}/files/boot.sh.tftpl", { sha256 = var.spin_boot_sha256, role = role, config = doc })
  }
}
