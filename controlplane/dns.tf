# app.<domain> is the dashboard and *.app.<domain> every workspace and the relay runners dial;
# both are the proxy, at its elastic IP. Only where the installation keeps its DNS in Route 53:
# with DNS kept elsewhere, the two records are the operator's, pointed at the proxy_ip output.
#
# The runners do not use them: each resolves tunnel.app.<domain> to the proxy's private address
# in its own /etc/hosts (the runners module), so the relay never leaves the VPC and no private
# zone is paid for to say so.
resource "aws_route53_record" "app" {
  for_each = var.route53_zone_id == "" ? toset([]) : toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = var.route53_zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.proxy.public_ip]
}
