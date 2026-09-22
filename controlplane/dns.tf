# app.<domain> is the dashboard and *.app.<domain> every workspace and the relay runners dial;
# both are the proxy, at its elastic IP.
resource "aws_route53_record" "app" {
  for_each = var.route53_zone_id == "" ? toset([]) : toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = var.route53_zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.proxy.public_ip]
}

# The same names inside the VPC, at the proxy's private address. A runner dials its relay at
# tunnel.app.<domain>; answered with the public address, that connection went out through the
# internet gateway and back in — billed, and from a public address the proxy has to let in,
# which is what kept 443 open to the world. Answered here, it never leaves the VPC, and
# proxy_allowed_cidrs can be the users' networks alone. The certificate is the same either way.
resource "aws_route53_zone" "inside" {
  name    = "app.${var.domain}"
  comment = "${var.name}: the proxy by its private address, for what is inside the VPC"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  tags = local.tags
}

resource "aws_route53_record" "inside" {
  for_each = toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = aws_route53_zone.inside.zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [local.proxy_ip]
}
