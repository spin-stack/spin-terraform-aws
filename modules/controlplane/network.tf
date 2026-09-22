# Public subnets and no NAT gateway. A NAT is $32 a month plus a charge per GB before anything
# runs, and nothing here needs one: every machine has its own public address, and the bucket is
# reached through the gateway endpoint, which is free and keeps volume traffic off the internet.
# Nothing listens on a runner (spin's docs/network/README.md), and the control plane answers nothing
# from the internet either: its public address is a way out. The proxy, on a machine of its
# own, is the one thing the internet reaches - 80 and 443 - and the control plane's 8080 is
# the proxy's and the runners' alone.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  zones   = slice(data.aws_availability_zones.available.names, 0, var.availability_zones)
  region  = data.aws_region.current.region
  account = data.aws_caller_identity.current.account_id
  tags    = merge({ "spin:installation" = var.name }, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = var.name })
}

resource "aws_subnet" "public" {
  count                   = length(local.zones)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${var.name}-${local.zones[count.index]}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The bucket's only way in: its policy refuses object reads and writes that do not come
# through here, so a runner's credential copied off the machine opens nothing.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]
  tags              = merge(local.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "controlplane" {
  name        = "${var.name}-controlplane"
  description = "spin control plane: 8080 from the proxy and runners only, nothing from the internet"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-controlplane" })
}

# The control plane takes nothing from the internet: its public address is only a way out, and
# a security group with no rule for it is a machine nothing out there reaches. 8080 is the
# proxy's (below) and the runners' (the runners module adds theirs).
resource "aws_vpc_security_group_ingress_rule" "controlplane_from_proxy" {
  security_group_id            = aws_security_group.controlplane.id
  referenced_security_group_id = aws_security_group.proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  description                  = "the proxy"
}

# Out, only the web: images, the machine release, GitHub, STS, SSM, Auto Scaling and the bucket
# through its endpoint, all 443 (80 for apt). The catalog is rds.tf's own rule.
resource "aws_vpc_security_group_egress_rule" "controlplane" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.controlplane.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "the web"
}

# The proxy is the only machine the internet reaches: 80 for the ACME HTTP challenge and the
# redirect, 443 for the dashboard, workspaces and the relay runners dial out to
# (tunnel.app.<domain>).
resource "aws_security_group" "proxy" {
  name        = "${var.name}-proxy"
  description = "spin proxy: 80 and 443 from anywhere; out to the control plane and the web"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-proxy" })
}

# 80 from anywhere: Let's Encrypt's HTTP challenge comes from addresses it does not publish, and
# the rest of 80 is a redirect.
resource "aws_vpc_security_group_ingress_rule" "proxy_http" {
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "ACME and the redirect"
}

# 443 from the networks the installation's users are on - anywhere, unless it says otherwise.
resource "aws_vpc_security_group_ingress_rule" "proxy_https" {
  for_each          = toset(var.proxy_allowed_cidrs)
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "users"
}

# And from inside the VPC, whatever the list says: the runners' relay, which reaches the proxy
# by its private name (proxy.<zone>), and so never needs to be among the users' networks.
resource "aws_vpc_security_group_ingress_rule" "proxy_https_vpc" {
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "the runners' relay"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_controlplane" {
  security_group_id            = aws_security_group.proxy.id
  referenced_security_group_id = aws_security_group.controlplane.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  description                  = "the control plane"
}

# ACME, the proxy's image and SSM; 80 for apt.
resource "aws_vpc_security_group_egress_rule" "proxy_web" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "the web"
}
