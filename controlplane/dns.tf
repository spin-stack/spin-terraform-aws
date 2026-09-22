# The installation's own names, resolved only inside its VPC: what a component dials another
# by, so a machine replaced — or, updating, one standing beside the other — is a record changed
# and not an address baked into every runner's configuration and the control plane's
# certificate. The runners' relay is the one exception: it is tunnel.app.<domain>, a name the
# control plane hands out and the proxy's certificate carries, which each runner resolves to
# the proxy's private address in its own /etc/hosts (the runners module), so the relay never
# leaves the VPC.
resource "aws_route53_zone" "internal" {
  name    = var.internal_zone
  comment = "${var.name}: its components, to each other"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  tags = local.tags
}

# A minute: what a replaced machine waits for the others to follow it.
resource "aws_route53_record" "internal" {
  for_each = {
    (local.cp_host)    = local.private_ip
    (local.proxy_host) = local.proxy_ip
  }
  zone_id = aws_route53_zone.internal.zone_id
  name    = each.key
  type    = "A"
  ttl     = 60
  records = [each.value]
}

# app.<domain> is the dashboard and *.app.<domain> every workspace and the relay runners dial;
# both are the proxy, at its elastic IP. Only where the installation keeps its DNS in Route 53:
# with DNS kept elsewhere, the two records are the operator's, pointed at the proxy_ip output.
resource "aws_route53_record" "app" {
  for_each = var.route53_zone_id == "" ? toset([]) : toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = var.route53_zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.proxy.public_ip]
}
