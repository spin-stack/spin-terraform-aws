# The installation's own names, resolved only inside its VPC: what a component dials another
# by, so a machine replaced - or, updating, one standing beside the other - is a record changed
# and not an address baked into every runner's configuration and the control plane's
# certificate. The runners reach the relay by proxy.<zone> too, checking its certificate as the
# name the control plane hands out (spin-install runner --relay-dial), so it never leaves the VPC.
#
# The records are the machines' own. Each writes its name when it is about to serve under it
# (spin-boot, spin's internal/installation/boot) - a control plane just before it takes the term, a proxy once
# Caddy answers - which is the moment an update moves the installation to it; Terraform, which
# does not know the address of a machine an autoscaling group has not started, writes none.
# force_destroy, because a destroy would otherwise refuse the records it did not make.
resource "aws_route53_zone" "internal" {
  name          = var.internal_zone
  comment       = "${local.name}: its components, to each other"
  force_destroy = true
  vpc {
    vpc_id = aws_vpc.this.id
  }
  tags = merge(local.tags, { "spin:role" = "dns" })
}

locals {
  # Ten seconds: how long a client may keep dialling the machine an update just replaced.
  internal_record_ttl = 10
}

# How long a name that is not there yet stays not there: the lesser of the SOA's TTL and its
# minimum, 900 seconds as Route 53 makes a zone. A proxy that asked for cp.<zone> 14 seconds
# before the control plane wrote it waited those 15 minutes (spin-terraform-aws run
# 45691754153). The rest is the SOA Route 53 makes a private zone.
resource "aws_route53_record" "internal_soa" {
  zone_id         = aws_route53_zone.internal.zone_id
  name            = aws_route53_zone.internal.name
  type            = "SOA"
  ttl             = local.internal_record_ttl
  allow_overwrite = true
  records         = ["${trimsuffix(aws_route53_zone.internal.primary_name_server, ".")}. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 ${local.internal_record_ttl}"]
}

# The domain's public zone: whoever registered it points its nameservers here (the name_servers
# output). A new zone is new nameservers, and the domain resolves nothing until the registrar is
# changed again - so it is replaced only by a destroy. force_destroy, for the same reason as the
# internal zone's.
resource "aws_route53_zone" "public" {
  name          = var.domain
  comment       = "${local.name}: the installation, to the internet"
  force_destroy = true
  tags          = merge(local.tags, { "spin:role" = "dns" })
}

# app.<domain> is the dashboard, tunnel.app.<domain> the relay runners dial, agents.<domain> the
# agent's client the dashboard frames, id.<domain> the identity issuer
# and *.ws.<domain> every workspace; all are the proxy, at its elastic IP. The workspaces are under
# a name of their own so that a workspace is never the dashboard's subdomain: what a tenant serves
# there can set no cookie the dashboard reads, and no workspace name can be the relay's.
resource "aws_route53_record" "app" {
  for_each = toset(["app.${var.domain}", "tunnel.app.${var.domain}", "agents.${var.domain}", "id.${var.domain}", "*.ws.${var.domain}"])
  zone_id  = aws_route53_zone.public.zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.proxy.public_ip]
}
