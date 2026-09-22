# One machine, and a volume that outlives it. Everything the installation cannot lose is on the
# volume — /etc/spin-stack (the encryption key, the database's password) and /var/lib/spin-stack
# (Postgres, the CA) — so a replaced instance mounts it and the installer, run again, keeps what
# is there. The encryption key is also copied to SSM on the first start: with it and the hourly
# catalog backup in the bucket, a lost volume is `controlplane catalog restore`, not a new
# installation.

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
  # Fixed, so the address in the control plane's certificate — and in every runner's
  # configuration — is the same across a replaced instance.
  private_ip = cidrhost(aws_subnet.public[0].cidr_block, 10)
  url        = "https://${local.private_ip}:8080"
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

resource "aws_ebs_volume" "data" {
  availability_zone = local.zones[0]
  size              = var.data_volume_gb
  type              = "gp3"
  encrypted         = true
  tags              = merge(local.tags, { Name = "${var.name}-controlplane-data", "spin:snapshot" = var.name })
  lifecycle {
    prevent_destroy = true
  }
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
    # Two hops: the control plane runs in a container, and its SDK reaches the instance role
    # through the bridge. One hop and it finds no credentials, and the store is refused.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    name                    = var.name
    region                  = local.region
    spin_version            = var.spin_version
    private_ip              = local.private_ip
    proxy_ip                = local.proxy_ip
    bucket                  = aws_s3_bucket.volumes.bucket
    role_arn                = aws_iam_role.runner_scope.arn
    data_volume             = aws_ebs_volume.data.id
    token_parameter         = local.token_parameter
    ca_parameter            = local.ca_parameter
    key_parameter           = local.key_parameter
    pool_flags              = join(" ", var.pool_token_flags)
    rotation                = var.pool_token_rotation
    installation            = yamlencode(local.installation)
    collector               = local.collector
    metric_interval         = local.metric_interval
    alloy_version           = local.telemetry ? var.grafana_cloud.alloy_version : ""
    alloy_sha256            = local.telemetry ? var.grafana_cloud.alloy_sha256 : ""
    grafana_token_parameter = local.token_parameter_grafana
    alloy_config = local.telemetry ? templatefile("${path.module}/alloy.alloy.tftpl", {
      listen        = local.private_ip
      otlp_endpoint = var.grafana_cloud.otlp_endpoint
      instance_id   = var.grafana_cloud.instance_id
      log_severity  = var.grafana_cloud.log_severity
    }) : ""
    token_expiry = "${tonumber(trimsuffix(var.pool_token_rotation, "h")) * 4}h"
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
    aws_vpc_endpoint.s3,
  ]
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.controlplane.id
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

data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name                 = "${var.name}-dlm"
  assume_role_policy   = data.aws_iam_policy_document.dlm_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "data" {
  description        = "${var.name} control plane data volume"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"
  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { "spin:snapshot" = var.name }
    schedule {
      name = "daily"
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["05:00"]
      }
      retain_rule {
        count = var.snapshot_retention_days
      }
      copy_tags = true
    }
  }
  tags = local.tags
}
