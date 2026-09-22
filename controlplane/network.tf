# Public subnets and no NAT gateway. A NAT is $32 a month plus a charge per GB before anything
# runs, and nothing here needs one: every machine has its own public address, and the bucket is
# reached through the gateway endpoint, which is free and keeps volume traffic off the internet.
# Nothing listens on a runner (docs/network/README.md), so a public address there reaches
# nothing; the control plane answers 80 and 443 to the world and 8080 only to runners.

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
  description = "spin control plane and proxy: 80 and 443 from anywhere, 8080 from runners only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-controlplane" })
}

# 80 for the ACME HTTP challenge and the redirect; 443 for the dashboard, workspaces and the
# relay runners dial out to (tunnel.app.<domain>).
resource "aws_vpc_security_group_ingress_rule" "web" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.controlplane.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "the proxy"
}

resource "aws_vpc_security_group_egress_rule" "controlplane" {
  security_group_id = aws_security_group.controlplane.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "images, the machine release, ACME, STS and SSM"
}
