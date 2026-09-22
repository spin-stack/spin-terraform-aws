# The proxy on a machine of its own: the one address the internet is given, and nothing on it
# but Caddy under Compose. Whatever reaches it — a flaw in Caddy, a request it mishandles —
# lands on a machine that holds a CA certificate and its own TLS certificates, not on the one
# with the catalog, the encryption key and Postgres.

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

# The CA it trusts the control plane by, and nothing else: it holds no credential to the bucket
# or to anything the control plane has.
data "aws_iam_policy_document" "proxy" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.ca.arn]
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

resource "aws_instance" "proxy" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.proxy_instance_type
  subnet_id              = aws_subnet.public[0].id
  private_ip             = local.proxy_ip
  vpc_security_group_ids = [aws_security_group.proxy.id]
  iam_instance_profile   = aws_iam_instance_profile.proxy.name

  metadata_options {
    http_tokens = "required"
    # One hop: Caddy in its container has no business with the instance's role.
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/proxy_user_data.sh.tftpl", {
    region          = local.region
    spin_version    = var.spin_version
    domain          = var.domain
    acme_email      = var.acme_email
    controlplane    = local.url
    ca_parameter    = local.ca_parameter
    unpublished     = local.unpublished
    collector       = local.collector
    metric_interval = local.metric_interval
  })

  tags = merge(local.tags, { Name = "${var.name}-proxy" })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip_association" "proxy" {
  allocation_id = aws_eip.proxy.id
  instance_id   = aws_instance.proxy.id
}
