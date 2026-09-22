# The proxy on a machine of its own: the one address the internet is given, and nothing on it
# but Caddy. Whatever reaches it — a flaw in Caddy, a request it mishandles — lands on a machine
# that holds a CA certificate and its own TLS certificates, not on the one with the catalog and
# the encryption key.
#
# One proxy, replaced beside itself as the control plane is (instance.tf): the new machine
# restores the certificates the last one had from their bucket, starts Caddy, points
# proxy.<zone> at itself and takes the elastic IP, which is the moment the internet's
# connections move to it; then the group retires the old one.

# The proxy's own subnets, one per zone, where nothing else runs: the range the control plane
# takes a browser's address from (--trusted-proxy). A runner, in the public subnets, cannot
# claim to be a proxy by being in the VPC.
resource "aws_subnet" "edge" {
  count                   = length(local.zones)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 136 + count.index)
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${var.name}-edge-${local.zones[count.index]}" })
}

resource "aws_route_table_association" "edge" {
  count          = length(aws_subnet.edge)
  subnet_id      = aws_subnet.edge[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_iam_role" "proxy" {
  name                 = "${var.name}-proxy"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  tags                 = local.tags
}

resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The CA it trusts the control plane by; its own certificates' bucket; and, to take the
# installation over, its name, the elastic IP and its group's word. No credential to the volumes'
# bucket or to anything the control plane has.
data "aws_iam_policy_document" "proxy" {
  statement {
    sid       = "TheControlPlanesCA"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.ca.arn]
  }
  statement {
    sid       = "ItsCertificates"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.certificates.arn, "${aws_s3_bucket.certificates.arn}/*"]
  }
  statement {
    sid       = "ItsName"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.internal.arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = [local.proxy_host]
    }
  }
  # The one address, onto a proxy of this installation.
  statement {
    sid       = "TheAddress"
    actions   = ["ec2:AssociateAddress"]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:elastic-ip/${aws_eip.proxy.allocation_id}"]
  }
  statement {
    sid       = "OntoAProxy"
    actions   = ["ec2:AssociateAddress"]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:instance/*", "arn:aws:ec2:${local.region}:${local.account}:network-interface/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/spin:role"
      values   = ["proxy"]
    }
  }
  statement {
    sid       = "InService"
    actions   = ["autoscaling:CompleteLifecycleAction"]
    resources = ["arn:aws:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.proxy_group}"]
  }
}

resource "aws_iam_role_policy" "proxy" {
  name   = "spin"
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy.json
}

resource "aws_iam_instance_profile" "proxy" {
  name = "${var.name}-proxy"
  role = aws_iam_role.proxy.name
  tags = local.tags
}

resource "aws_eip" "proxy" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name}-proxy" })
}

# Caddy's certificates and ACME account, kept for the next proxy: versioned, and no Object Lock —
# a certificate is replaced every sixty days and an old one is worth nothing. Reached, like the
# volumes' bucket, only through the VPC's endpoint.
resource "aws_s3_bucket" "certificates" {
  bucket        = "${var.name}-proxy-${local.account}-${local.region}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "certificates" {
  bucket = aws_s3_bucket.certificates.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "certificates" {
  bucket = aws_s3_bucket.certificates.id
  rule {
    id     = "old-certificates"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "certificates" {
  bucket                  = aws_s3_bucket.certificates.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "certificates" {
  bucket = aws_s3_bucket.certificates.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "certificates" {
  bucket = aws_s3_bucket.certificates.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "certificates" {
  statement {
    sid     = "ObjectsOnlyFromTheVPC"
    effect  = "Deny"
    actions = ["s3:GetObject*", "s3:PutObject*", "s3:DeleteObject*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.certificates.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.s3.id]
    }
  }
  statement {
    sid     = "TLSOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.certificates.arn, "${aws_s3_bucket.certificates.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "certificates" {
  bucket     = aws_s3_bucket.certificates.id
  policy     = data.aws_iam_policy_document.certificates.json
  depends_on = [aws_s3_bucket_public_access_block.certificates]
}

locals {
  proxy_files = {
    "/usr/local/lib/spin/lifecycle.sh" = { mode = "0644", content = local.lifecycle_sh["proxy"] }
    "/usr/local/sbin/spin-proxy-certificates" = {
      mode = "0755"
      content = templatefile("${path.module}/files/spin-proxy-certificates.tftpl", {
        region = local.region
        bucket = aws_s3_bucket.certificates.bucket
      })
    }
    "/etc/systemd/system/spin-proxy-certificates.service" = {
      mode = "0644", content = file("${path.module}/files/spin-proxy-certificates.service")
    }
    "/etc/systemd/system/spin-proxy-certificates.timer" = {
      mode = "0644", content = file("${path.module}/files/spin-proxy-certificates.timer")
    }
  }

  proxy_user_data = templatefile("${path.module}/proxy_user_data.sh.tftpl", {
    region          = local.region
    fetch_release   = local.fetch_release
    write_files     = local.write_files["proxy"]
    domain          = var.domain
    acme_email      = var.acme_email
    controlplane    = local.url
    proxy_host      = local.proxy_host
    allocation_id   = aws_eip.proxy.allocation_id
    ca_parameter    = local.ca_parameter
    unpublished     = local.unpublished
    collector       = local.collector
    metric_interval = local.metric_interval
  })
}

resource "aws_launch_template" "proxy" {
  name_prefix            = "${var.name}-proxy-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.proxy_instance_type
  vpc_security_group_ids = [aws_security_group.proxy.id]
  user_data              = base64encode(local.proxy_user_data)

  iam_instance_profile {
    arn = aws_iam_instance_profile.proxy.arn
  }

  metadata_options {
    http_tokens = "required"
    # One hop: nothing but the machine itself asks for the instance's role.
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
    tags          = merge(local.tags, { Name = "${var.name}-proxy", "spin:role" = "proxy" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-proxy" })
  }
  tags = local.tags
}

resource "aws_autoscaling_group" "proxy" {
  name                = local.proxy_group
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = aws_subnet.edge[*].id
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.proxy.id
    version = aws_launch_template.proxy.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 60
    }
  }

  # A first proxy waits for the control plane's CA as long as the control plane takes to come up.
  initial_lifecycle_hook {
    name                 = "ready"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    heartbeat_timeout    = 2400
    default_result       = "ABANDON"
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${var.name}-proxy" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  depends_on = [aws_route.internet, aws_s3_bucket_policy.certificates, aws_iam_role_policy.proxy]
}
