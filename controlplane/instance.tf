# One machine that holds nothing the installation cannot lose. The catalog is RDS (rds.tf), the
# CA and the KEK are sealed in it, and the encryption key that opens them is in SSM from the
# first start on: a replaced instance reads the key back, installs the same release and serves
# the same catalog.

# The newest of Canonical's own images of the release: owned by Canonical's account, so a
# public image named like one is not picked up.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-*-${var.ubuntu_release}-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  # The addresses the internal zone's records hold. The components dial the names — the control
  # plane's certificate carries cp.<zone> and every runner is configured with it — so these are
  # the records' business alone.
  private_ip = cidrhost(aws_subnet.public[0].cidr_block, 10)
  cp_host    = "cp.${var.internal_zone}"
  proxy_host = "proxy.${var.internal_zone}"
  url        = "https://${local.cp_host}:8080"
  # The proxy's, fixed for the same reason: the control plane takes its word about a browser's
  # address by it (--trusted-proxy).
  proxy_ip = cidrhost(aws_subnet.public[0].cidr_block, 11)

  token_parameter = "/${var.name}/runner-registration-token"
  ca_parameter    = "/${var.name}/controlplane-ca"
  key_parameter   = "/${var.name}/controlplane-encryption-key"
  # What the runners wait for: the control plane has not published anything yet.
  unpublished = "unpublished"

  # The group the runners module makes; its name is the contract between the two modules.
  runner_group = "${var.name}-runners"

  # How every machine of the installation gets a release file: cosign by its pinned SHA-256,
  # then the file and its bundle, verified against this repository's release workflow at the
  # version's tag before anything in it runs. Defines `release <file>`.
  fetch_release = templatefile("${path.module}/files/fetch-release.sh.tftpl", {
    spin_version = var.spin_version
    cosign       = var.cosign
  })

  # The operator's config file, with the settings the control plane sizes the runners by.
  operator = var.installation_config == "" ? {} : yamldecode(var.installation_config)
  installation = merge(local.operator, {
    settings = merge(try(local.operator.settings, {}), merge({
      autoscaling_group        = local.runner_group
      autoscaling_region       = local.region
      autoscaling_idle_minutes = var.runner_idle_minutes
      }, var.quiet_hours == "" ? {} : {
      autoscaling_quiet_hours = var.quiet_hours
      autoscaling_time_zone   = var.time_zone
    }))
  })
}

resource "aws_instance" "controlplane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  private_ip             = local.private_ip
  vpc_security_group_ids = [aws_security_group.controlplane.id]
  iam_instance_profile   = aws_iam_instance_profile.controlplane.name

  metadata_options {
    http_tokens = "required"
    # One hop: every process that asks for the role's credentials is on the machine itself.
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    name          = var.name
    region        = local.region
    fetch_release = local.fetch_release
    write_files   = local.controlplane_write_files
    cp_host       = local.cp_host
    proxy_ip      = local.proxy_ip
    bucket        = aws_s3_bucket.volumes.bucket
    role_arn      = aws_iam_role.runner_scope.arn
    database_host = aws_db_instance.catalog.address
    database_url  = local.database_url
    # The secret's ARN, which is not the secret: the machine reads it with its role, once.
    database_admin  = aws_db_instance.catalog.master_user_secret[0].secret_arn
    key_parameter   = local.key_parameter
    ca_parameter    = local.ca_parameter
    collector       = local.collector
    metric_interval = local.metric_interval
    alloy_version   = local.telemetry ? var.grafana_cloud.alloy_version : ""
    alloy_sha256    = local.telemetry ? var.grafana_cloud.alloy_sha256 : ""
  })

  tags = merge(local.tags, { Name = "${var.name}-controlplane" })

  lifecycle {
    # A new Ubuntu image is not a reason to replace the control plane; replacing it is a
    # decision, taken with `-replace`.
    ignore_changes = [ami, user_data]
  }

  depends_on = [
    # The installer checks the bucket and a credential minted under the role; both exist and
    # the bucket answers only through the endpoint.
    aws_s3_bucket_policy.volumes,
    aws_s3_bucket_object_lock_configuration.volumes,
    aws_iam_role_policy.controlplane,
    aws_iam_role_policy.runner_scope,
    aws_route.internet,
    # Its own collector is dialled by name, and so is it by everything that waits for it.
    aws_route53_record.internal,
    aws_vpc_endpoint.s3,
    aws_vpc_security_group_egress_rule.controlplane_to_database,
  ]
}

# Where the control plane publishes what a runner needs to join, created here so the runners'
# role can be given exactly these. The values are the control plane's to write.
resource "aws_ssm_parameter" "token" {
  name        = local.token_parameter
  description = "A pool's registration token for ${var.name}'s runners, rotated by the control plane"
  type        = "SecureString"
  value       = local.unpublished
  tags        = local.tags
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "ca" {
  name        = local.ca_parameter
  description = "The CA ${var.name}'s runners trust the control plane by"
  type        = "String"
  value       = local.unpublished
  tags        = local.tags
  lifecycle {
    ignore_changes = [value]
  }
}
