# One machine that holds nothing the installation cannot lose. The database runs on it and is
# archived as it is written to a bucket of its own (database_bucket.tf), the key is agreed with KMS
# at every start (attested_key.tf) and the CA is in SSM (secrets.tf): a replaced instance reads its
# document, restores the database from the archive and serves it.

# Spin OS of this installation's release (spin-stack/ami), one image per role: the image is the
# release and the role - a machine of it runs that release's part for that role and no other, from
# a root it cannot write, under a Secure Boot key of that role's - so the release names the images.
# Where each is, role by role and region by region, is images.json at this repository's root, which
# spin-stack/ami's publish updates by a pull request: ids this module's commit names, so an image
# published again for a release reaches an installation by the module's ref moving, never by
# whatever apply happens to follow it. image_ids names them outright - builds of your own.
locals {
  roles           = ["control-plane", "runner", "proxy"]
  images          = jsondecode(file("${path.module}/../../images.json"))
  released_images = { for role in local.roles : role => try(local.images[var.spin_version][role][local.region], "") }
  images_wanted   = length(var.image_ids) > 0 ? var.image_ids : local.released_images
}

# No owners: the image is named by its id, which a reviewed images.json or the operator gives -
# there is no search whose result an owner would narrow.
#trivy:ignore:AWS-0344
data "aws_ami" "spin_os" {
  for_each           = toset(local.roles)
  include_deprecated = true
  filter {
    name   = "image-id"
    values = [local.images_wanted[each.key]]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "boot-mode"
    values = ["uefi"]
  }
  lifecycle {
    precondition {
      condition     = local.images_wanted[each.key] != ""
      error_message = "${var.spin_version} has no Spin OS image for the ${each.key} in ${local.region}: images.json has it in [${join(", ", keys(try(local.images[var.spin_version][each.key], {})))}]. Publish it there (spin-stack/ami) and move this module's ref, or name the images with image_ids."
    }
  }
}

locals {
  image = { for role, ami in data.aws_ami.spin_os : role => ami.id }
  # Each image's root device, where a machine's root volume is sized: Spin OS's is /dev/xvda.
  root_device = { for role, ami in data.aws_ami.spin_os : role => ami.root_device_name }

  # What each machine starts on, as the tag that makes a change to it a new launch template: a
  # machine reads its document at every start, and nothing else would roll the change out. The
  # control plane's includes the installation's configuration, which it applies when it starts.
  controlplane_starts_on = sha256(join("\n", [yamlencode(local.controlplane_document), yamlencode(local.installation)]))
  proxy_starts_on        = sha256(yamlencode(local.proxy_document))

  # The names the components dial each other by - the control plane's certificate carries
  # cp.<zone>, and every runner and proxy is configured with it - which each machine points at
  # itself (dns.tf). No address is fixed: an update stands a new machine beside the old.
  cp_host    = "cp.${var.internal_zone}"
  proxy_host = "proxy.${var.internal_zone}"
  url        = "https://${local.cp_host}:8080"

  # The groups of one each machine is in, by name, so a machine can speak for itself to its own.
  controlplane_group = "${local.name}-controlplane"
  proxy_group        = "${local.name}-proxy"

  # The group the runners module makes; its name is the contract between the two modules.
  runner_group = "${local.name}-runners"
}

data "aws_ec2_instance_type" "controlplane" {
  instance_type = var.instance_type
}

data "aws_ec2_instance_type" "proxy" {
  instance_type = var.proxy_instance_type
}

resource "aws_launch_template" "controlplane" {
  name_prefix            = "${local.name}-controlplane-"
  image_id               = local.image["control-plane"]
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.controlplane.id]
  user_data              = base64encode(local.user_data["control-plane"])

  iam_instance_profile {
    arn = aws_iam_instance_profile.controlplane.arn
  }

  metadata_options {
    http_tokens = "required"
    # One hop: every process that asks for the role's credentials is on the machine itself.
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = local.root_device["control-plane"]
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_gb
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-controlplane", "spin:role" = "controlplane", "spin:starts-on" = local.controlplane_starts_on })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-controlplane" })
  }
  tags = local.tags
}

# One control plane, replaced beside itself. A change to what a machine is - the release, the
# image, the size - is a new launch template version, and the refresh starts a machine of it
# before retiring the old one (100% healthy, up to 200%). The new machine points cp.<zone> at
# itself and starts, which takes the term: the old one, superseded, closes and stays down, and
# every runner and the proxy reconnect to the name within seconds. The workspaces never stop:
# they are the runners'. The launch hook holds the refresh until the new machine leads, and
# abandons it - leaving the old - if it never does (spin's internal/boot).
#
# A change to the document alone is not a new template version: the document is read at every
# start, and the refresh that brings it in is `aws autoscaling start-instance-refresh`.
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
      # A refresh whose machine never comes into service puts the group back on the template it
      # had: otherwise the old machine goes on serving while the group holds the one that failed,
      # and the next replacement - an unhealthy machine, a zone lost - boots that.
      auto_rollback = true
    }
  }

  initial_lifecycle_hook {
    name                 = "ready"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    # The boot beats while it works, so this is how long it may be silent - not how long the
    # release, the database and the base image's first look take.
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
    for_each = merge(local.tags, { Name = "${local.name}-controlplane" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  depends_on = [
    # What the machine starts on, and what the document names.
    aws_ssm_parameter.controlplane_config,
    aws_ssm_parameter.installation,
    aws_kms_key.encryption,
    aws_ssm_parameter.ca,
    aws_ssm_parameter.admin_password,
    # The installer checks the bucket and a credential minted under the role; both exist and
    # the bucket answers only through the endpoint.
    aws_s3_bucket_policy.volumes,
    aws_s3_bucket_object_lock_configuration.volumes,
    # The database's archive, which the first boot starts and every later one restores from.
    aws_s3_bucket_policy.database,
    aws_s3_bucket_object_lock_configuration.database,
    aws_iam_role_policy.controlplane,
    aws_iam_role_policy.runner_scope,
    aws_route.internet,
    aws_vpc_endpoint.s3,
  ]
}
