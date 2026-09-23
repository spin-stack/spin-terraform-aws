# An autoscaling group of runners that join by themselves: each reads its document, proves to the
# control plane who it is with its instance role (spin's internal/domain/hostjoin) and joins under
# the policy the installation declares for that role. There is no token to publish or read.
# Nothing reaches a runner - its group has no ingress - and it reaches the control plane on 8080,
# the proxy's relay on 443 and the bucket through the gateway endpoint.

# The newest of Canonical's own images of the release: owned by Canonical's account, so a
# public image named like one is not picked up. A new one reaches hosts the group starts after
# it is published, since the template is re-applied with it.
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
  name = var.controlplane.name
  tags = merge({ "spin:installation" = local.name }, var.tags)
}

resource "aws_security_group" "runner" {
  name        = "${local.name}-runner"
  description = "spin runners: nothing in, everything out"
  vpc_id      = var.controlplane.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-runner" })
}

resource "aws_vpc_security_group_egress_rule" "runner" {
  security_group_id = aws_security_group.runner.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "the control plane, the relay, the bucket, and the egress of workspaces, which spin filters"
}

# The collector's port, where the installation has one.
resource "aws_vpc_security_group_ingress_rule" "collector_from_runners" {
  count                        = var.controlplane.collector == "" ? 0 : 1
  security_group_id            = var.controlplane.security_group_id
  referenced_security_group_id = aws_security_group.runner.id
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  description                  = "telemetry from spin runners"
}

resource "aws_vpc_security_group_ingress_rule" "controlplane_from_runners" {
  security_group_id            = var.controlplane.security_group_id
  referenced_security_group_id = aws_security_group.runner.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  description                  = "spin runners"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name                 = "${local.name}-runner"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = var.controlplane.boundary_arn
  tags                 = local.tags
}

# Its document and nothing else: a runner's credential to the bucket is the control plane's to
# mint, an hour at a time and for its own volumes, and who it is needs no permission - STS answers
# GetCallerIdentity for any principal. Its instance role opens nothing a tenant who escaped a
# machine could use against another tenant.
data "aws_iam_policy_document" "runner" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [var.controlplane.runner_config_parameter_arn]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "spin"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_role_policy_attachment" "runner_boot_log" {
  role       = aws_iam_role.runner.name
  policy_arn = var.controlplane.boot_log_policy_arn
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  count      = var.session_manager ? 1 : 0
  role       = aws_iam_role.runner.name
  policy_arn = var.controlplane.session_manager_policy_arn
}

resource "aws_iam_instance_profile" "runner" {
  name = "${local.name}-runner"
  role = aws_iam_role.runner.name
  tags = local.tags
}

resource "aws_launch_template" "runner" {
  name_prefix            = "${local.name}-runner-"
  image_id               = data.aws_ami.ubuntu.id
  vpc_security_group_ids = [aws_security_group.runner.id]
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner.arn
  }

  metadata_options {
    http_tokens = "required"
    # One hop: the runner is on the host, and a guest must never reach the metadata service
    # (netaddr.NodeNetworks drops 169.254.0.0/16 on top of this).
    http_put_response_hop_limit = 1
  }

  dynamic "cpu_options" {
    for_each = var.nested_virtualization ? [1] : []
    content {
      nested_virtualization = "enabled"
    }
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_gb
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.data_volume_gb > 0 ? [1] : []
    content {
      device_name = "/dev/sdf"
      ebs {
        volume_type           = "gp3"
        volume_size           = var.data_volume_gb
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  # The control plane module's: spin-boot by its digest, over the runners' document.
  user_data = base64encode(var.controlplane.runner_user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-runner" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-runner" })
  }
  tags = local.tags
}

resource "aws_autoscaling_group" "runner" {
  name                = "${local.name}-runners"
  vpc_zone_identifier = var.controlplane.subnet_ids
  # From none, and sized by the control plane (spin's internal/domain/autoscale): it starts a host when
  # a workspace waits for one and empties the group when nothing runs. Terraform sets neither
  # the size nor the name's contract with the control plane module, ${name}-runners, can change.
  min_size = 0
  max_size = var.max_hosts
  # A spot recommendation to leave starts the replacement first; the host being replaced then
  # leaves by the termination hook below, so its workspaces have somewhere to resume.
  capacity_rebalance = var.spot
  # Ten minutes to boot and install before the group asks: a runner is healthy when EC2 says it
  # is, and whether spin takes it is the control plane's to say (Admin -> Hosts).
  health_check_grace_period = 600

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = var.spot ? 0 : 100
      spot_allocation_strategy                 = "capacity-optimized-prioritized"
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.runner.id
        version            = "$Latest"
      }
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  # On the group from its first instance, so no host the group ever takes away skips the drain.
  initial_lifecycle_hook {
    name                 = "drain"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
    heartbeat_timeout    = var.drain_seconds
    # Left to expire: the host empties itself on seeing the state and does not answer the hook,
    # so it holds no permission to call the group.
    default_result = "CONTINUE"
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${local.name}-runner" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

