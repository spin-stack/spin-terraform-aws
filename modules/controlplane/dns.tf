# The installation's own names, resolved only inside its VPC: what a component dials another
# by, so a machine replaced - or, updating, one standing beside the other - is a record changed
# and not an address baked into every runner's configuration and the control plane's
# certificate. The runners reach the relay by proxy.<zone> too, checking its certificate as the
# name the control plane hands out (spin-install runner --relay-dial), so it never leaves the VPC.
#
# The records are the machines' own. Each writes its name when it is about to serve under it
# (files/lifecycle.sh.tftpl) - a control plane just before it takes the term, a proxy once
# Caddy answers - which is the moment an update moves the installation to it; Terraform, which
# does not know the address of a machine an autoscaling group has not started, writes none.
# force_destroy, because a destroy would otherwise refuse the records it did not make.
resource "aws_route53_zone" "internal" {
  name          = var.internal_zone
  comment       = "${var.name}: its components, to each other"
  force_destroy = true
  vpc {
    vpc_id = aws_vpc.this.id
  }
  tags = local.tags
}

locals {
  # Ten seconds: how long a client may keep dialling the machine an update just replaced.
  internal_record_ttl = 10
}

# The domain's public zone: whoever registered it points its nameservers here (the name_servers
# output). A new zone is new nameservers, and the domain resolves nothing until the registrar is
# changed again - so it is replaced only by a destroy. force_destroy, for the same reason as the
# internal zone's.
resource "aws_route53_zone" "public" {
  name          = var.domain
  comment       = "${var.name}: the installation, to the internet"
  force_destroy = true
  tags          = local.tags
}

# app.<domain> is the dashboard and *.app.<domain> every workspace and the relay runners dial;
# both are the proxy, at its elastic IP.
resource "aws_route53_record" "app" {
  for_each = toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = aws_route53_zone.public.zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.proxy.public_ip]
}
