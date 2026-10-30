# The runners: the launch template every host class's group starts its machines from, the role they
# run under, and the control plane's leave to make, hold and size those groups (one per class, the
# control plane's to make: spin's internal/controlplane/domain/hostclass). Each runner reads its
# document, proves to the control plane who it is with its instance role (spin's
# internal/domain/hostjoin) and joins under the policy the installation declares for that role.
# Nothing reaches a runner - it has no ingress - and it reaches the control plane on 8080, the
# proxy's relay on 443 and the bucket through the gateway endpoint.

# A runner boots the runner's image of the installation's release, which is the only one a
# runner's control plane serves (spin's CheckRelease refuses a runner of another). Nothing reaches
# into it, Session Manager included: the image carries no agent, and the role grants none. What a
# runner says is its serial console's, its boot log and its metrics; one that fails is replaced.

locals {
  name = var.controlplane.name
  # IAM's names carry the region (the control plane module's iam_name), as the control plane's do.
  iam_name = var.controlplane.iam_name
  tags     = merge({ "spin:installation" = local.name }, var.tags)
}

resource "aws_security_group" "runner" {
  name        = "${local.name}-runner"
  description = "spin runners: nothing in, everything out"
  vpc_id      = var.controlplane.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-runner" })
}

# Everything out: a workspace's egress is the installation's policy, enforced per machine by spin's
# nftables on the host (spin's docs/network), which a security group cannot tell one guest from
# another for.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "runner" {
  security_group_id = aws_security_group.runner.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "the control plane, the relay, the bucket, and the egress of workspaces, which spin filters"
}

# The collector's port: every process of the installation pushes to it (the control plane
# module's telemetry.tf).
resource "aws_vpc_security_group_ingress_rule" "collector_from_runners" {
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
  name                 = "${local.iam_name}-runner"
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
    actions   = ["s3:GetObject"]
    resources = [var.controlplane.runner_document_arn]
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

resource "aws_iam_instance_profile" "runner" {
  name = "${local.iam_name}-runner"
  role = aws_iam_role.runner.name
  tags = local.tags
}

resource "aws_launch_template" "runner" {
  # By name: the control plane makes each host class's group from it, and the name is what it is
  # told (its autoscaling_fleet setting) before the template's id exists.
  name                   = var.runners.launch_template
  image_id               = var.controlplane.images["runner"].id
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
    for_each = var.runners.nested_virtualization ? [1] : []
    content {
      nested_virtualization = "enabled"
    }
  }

  block_device_mappings {
    device_name = var.controlplane.images["runner"].root_device
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_gb
      encrypted             = true
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.runners.data_volume_gb > 0 ? [1] : []
    content {
      device_name = "/dev/sdf"
      ebs {
        volume_type           = "gp3"
        volume_size           = var.runners.data_volume_gb
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  # The control plane module's: the runner role and the runners' document, as credentials.
  user_data = base64encode(var.controlplane.runner_user_data)

  # spin:role is how the bill is read by role (a cost allocation tag, bootstrap/cost.tf); no policy
  # here decides anything by a runner's.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-runner", "spin:role" = "runner" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-runner", "spin:role" = "runner" })
  }
  tags = local.tags
}


# The runners' groups are the control plane's: one per host class, which it makes from this
# template, holds to its class and sizes (spin's internal/controlplane/domain/autoscale). Each is
# named <name>-runners-<class> and carries the installation's tag, and what the role may do to a
# group is held to both - nothing of another installation's, or of the control plane's and the
# proxy's own groups of one. Granted here, beside the template, because what makes a group is
# leave to start this template and to pass its role, and no other: the control plane decides
# what kind of machine a runner is, never what it boots.
data "aws_partition" "current" {}

locals {
  groups_arn = "arn:${data.aws_partition.current.partition}:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/${local.name}-runners-*"
}

data "aws_iam_policy_document" "controlplane_fleet" {
  statement {
    sid       = "MakeTheRunnersGroups"
    actions   = ["autoscaling:CreateAutoScalingGroup", "autoscaling:CreateOrUpdateTags", "autoscaling:PutLifecycleHook"]
    resources = [local.groups_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/spin:installation"
      values   = [local.name]
    }
  }
  statement {
    sid = "HoldAndSizeTheRunnersGroups"
    actions = [
      "autoscaling:UpdateAutoScalingGroup", "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup", "autoscaling:StartInstanceRefresh",
      "autoscaling:DeleteAutoScalingGroup", "autoscaling:PutLifecycleHook",
    ]
    resources = [local.groups_arn]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/spin:installation"
      values   = [local.name]
    }
  }
  # Describe has no resource-level permission. The groups' activities are how the control plane
  # says why a host it asked for did not come (spin#702), and a machine's group is its class.
  statement {
    sid = "SeeTheRunners"
    actions = [
      "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeAutoScalingInstances", "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }
  # What Auto Scaling asks of whoever names a launch template in a group: leave to start it,
  # which these hold to this template and nothing else, and to pass its machines' role.
  statement {
    sid       = "StartOnlyTheRunnersTemplate"
    actions   = ["ec2:RunInstances", "ec2:CreateTags"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "ec2:LaunchTemplate"
      values   = [aws_launch_template.runner.arn]
    }
  }
  statement {
    sid       = "PassTheRunnersRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.runner.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "controlplane_fleet" {
  name   = "runners"
  role   = var.runners.controlplane_role
  policy = data.aws_iam_policy_document.controlplane_fleet.json
}
