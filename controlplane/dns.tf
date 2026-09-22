# app.<domain> is the dashboard and *.app.<domain> every workspace and the relay runners dial;
# both are the proxy beside the control plane, at the elastic IP.
resource "aws_route53_record" "app" {
  for_each = var.route53_zone_id == "" ? toset([]) : toset(["app.${var.domain}", "*.app.${var.domain}"])
  zone_id  = var.route53_zone_id
  name     = each.value
  type     = "A"
  ttl      = 300
  records  = [aws_eip.controlplane.public_ip]
}
