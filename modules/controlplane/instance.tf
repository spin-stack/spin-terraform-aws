# One machine that holds nothing the installation cannot lose. The catalog is RDS (rds.tf), and
# the key and the CA are in SSM (secrets.tf): a replaced instance reads its document, installs the
# same release and serves the same catalog.

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

# The image the machines boot: the newest of the release when the installation's release last
# changed, and kept until it changes again. An image Canonical publishes is then picked up by an
# update, not by whatever apply happens to follow it - which would replace both machines for a
# change nobody asked for. image_id pins one outright.
resource "terraform_data" "image" {
  input            = var.image_id != "" ? var.image_id : data.aws_ami.ubuntu.id
  triggers_replace = [var.spin_version, var.ubuntu_release, var.image_id]
}

locals {
  image = terraform_data.image.output

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
  controlplane_group = "${var.name}-controlplane"
  proxy_group        = "${var.name}-proxy"

  # The group the runners module makes; its name is the contract between the two modules.
  runner_group = "${var.name}-runners"
}

data "aws_ec2_instance_type" "controlplane" {
  instance_type = var.instance_type
}

data "aws_ec2_instance_type" "proxy" {
  instance_type = var.proxy_instance_type
}

resource "aws_launch_template" "controlplane" {
  name_prefix            = "${var.name}-controlplane-"
  image_id               = local.image
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
    tags          = merge(local.tags, { Name = "${var.name}-controlplane", "spin:role" = "controlplane", "spin:starts-on" = local.controlplane_starts_on })
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
    for_each = merge(local.tags, { Name = "${var.name}-controlplane" })
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
    aws_ssm_parameter.encryption_key,
    aws_ssm_parameter.ca,
    aws_ssm_parameter.admin_password,
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
