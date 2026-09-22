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
  # The names the components dial each other by - the control plane's certificate carries
  # cp.<zone>, and every runner and proxy is configured with it - which each machine points at
  # itself (dns.tf). No address is fixed: an update stands a new machine beside the old.
  cp_host    = "cp.${var.internal_zone}"
  proxy_host = "proxy.${var.internal_zone}"
  url        = "https://${local.cp_host}:8080"

  # The groups of one each machine is in, by name, so a machine can speak for itself to its own.
  controlplane_group = "${var.name}-controlplane"
  proxy_group        = "${var.name}-proxy"

  # How often a booting machine says it is still going, and how long the group waits without
  # hearing it: five silent minutes is a machine to abandon, and the beats are what let a boot
  # that takes half an hour be a boot rather than a timeout.
  heartbeat_interval = 60
  heartbeat_timeout  = 300
  lifecycle_sh = { for role, group in { controlplane = local.controlplane_group, proxy = local.proxy_group } :
    role => templatefile("${path.module}/files/lifecycle.sh.tftpl", {
      region    = local.region
      zone_id   = aws_route53_zone.internal.zone_id
      group     = group
      ttl       = local.internal_record_ttl
      heartbeat = local.heartbeat_interval
    })
  }

  token_parameter = "/${var.name}/runner-registration-token"
  ca_parameter    = "/${var.name}/controlplane-ca"
  key_parameter   = "/${var.name}/controlplane-encryption-key"
  # What the runners wait for: the control plane has not published anything yet.
  unpublished = "unpublished"

  # The group the runners module makes; its name is the contract between the two modules.
  runner_group = "${var.name}-runners"

  # How every machine of the installation gets a release file: cosign and oras by their pinned
  # SHA-256, then the file and its bundle from the release's package, verified against spin's
  # release workflow at the version's tag before anything in it runs. Defines
  # `release <version> <file>`; the runners module is given it, and names the version its
  # control plane serves.
  fetch_release = templatefile("${path.module}/files/fetch-release.sh.tftpl", { cosign = var.cosign, oras = var.oras })

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

locals {
  controlplane_user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    name          = var.name
    region        = local.region
    spin_version  = var.spin_version
    fetch_release = local.fetch_release
    write_files   = local.write_files["controlplane"]
    cp_host       = local.cp_host
    # Whose word about a browser's address the control plane takes: the proxy's subnets, where
    # nothing but a proxy runs.
    trusted_proxies = join(",", aws_subnet.edge[*].cidr_block)
    bucket          = aws_s3_bucket.volumes.bucket
    role_arn        = aws_iam_role.runner_scope.arn
    database_host   = aws_db_instance.catalog.address
    database_url    = local.database_url
    # The secret's ARN, which is not the secret: the machine reads it with its role, once.
    database_admin  = aws_db_instance.catalog.master_user_secret[0].secret_arn
    key_parameter   = local.key_parameter
    ca_parameter    = local.ca_parameter
    collector       = local.collector
    metric_interval = local.metric_interval
    alloy_version   = local.telemetry ? var.grafana_cloud.alloy_version : ""
    alloy_sha256    = local.telemetry ? var.grafana_cloud.alloy_sha256 : ""
  })
}

resource "aws_launch_template" "controlplane" {
  name_prefix            = "${var.name}-controlplane-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.controlplane.id]
  # Gzipped, which cloud-init reads as it is: the script with the collector's configuration in it
  # is over the 16 KiB EC2 takes, and a third of that compressed.
  user_data = base64gzip(local.controlplane_user_data)

  iam_instance_profile {
    arn = aws_iam_instance_profile.controlplane.arn
  }

  metadata_options {
    http_tokens = "required"
    # One hop: every process that asks for the role's credentials is on the machine itself.
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-controlplane", "spin:role" = "controlplane" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-controlplane" })
  }
  tags = local.tags
}

# One control plane, replaced beside itself. A change to what a machine is - the release, the
# image, the size - is a new launch template version, and the refresh starts a machine of it
# before retiring the old one (100% healthy, up to 200%). The new machine points cp.<zone> at
# itself and starts, which takes the term: the old one, superseded, closes and stays down, and
# every runner and the proxy reconnect to the name within seconds. The workspaces never stop:
# they are the runners'. The launch hook holds the refresh until the new machine leads, and
# abandons it - leaving the old - if it never does.
resource "aws_autoscaling_group" "controlplane" {
  name                = local.controlplane_group
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = aws_subnet.public[*].id
  health_check_type   = "EC2"
  # Terraform does not wait for the machine: whether one is in service is the launch hook's
  # answer, which takes as long as a first boot takes and abandons the machine if it never
  # leads. A wait that gives up would mark this group as half-created, and the next apply
  # destroys and remakes a group whose only problem was a slow boot.
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.controlplane.id
    version = aws_launch_template.controlplane.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 60
    }
  }

  initial_lifecycle_hook {
    name                 = "ready"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    # The boot beats while it works (files/lifecycle.sh.tftpl), so this is how long it may be
    # silent - not how long the release, the database and the base image's first look take.
    heartbeat_timeout = local.heartbeat_timeout
    default_result    = "ABANDON"
  }

  # The hook is given at creation and never read back, so a group that has one reads as a group
  # with none - and the provider answers a hook it cannot see by replacing the group, which
  # takes the installation down to change nothing. The group's own hook is the authority.
  lifecycle {
    ignore_changes = [initial_lifecycle_hook]
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${var.name}-controlplane" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
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
