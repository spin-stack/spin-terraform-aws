output "dashboard" {
  description = "The installation's dashboard."
  value       = "https://app.${var.domain}"
}

# What an operator does next, in the order they do it, because an installation nobody can sign in
# to is an installation that is not up. /login offers the identity providers there are, and a new
# installation has none: the first way in is the setup page, with the first administrator this
# names.
output "first_sign_in" {
  description = "Where to go once the apply is done, and how to read the first administrator: the password is an SSM SecureString the control plane wrote, never Terraform's to hold."
  value = {
    url  = "https://app.${var.domain}/setup"
    user = "aws ssm get-parameter --name ${module.controlplane.bootstrap_user_parameter} --query Parameter.Value --output text"
    password = join(" ", ["aws ssm get-parameter --with-decryption --name",
    module.controlplane.bootstrap_password_parameter, "--query Parameter.Value --output text"])
  }
}

output "proxy_ip" {
  description = "The proxy's elastic IP, where app.<domain> and *.app.<domain> point: the one address of the installation the internet reaches."
  value       = module.controlplane.proxy_ip
}

output "controlplane_group" {
  description = "The control plane's group of one. Its machine, reached with `aws ssm start-session --target <instance>`, is where `sudo spin-controlplane bootstrap-password` prints the first administrator's password."
  value       = module.controlplane.controlplane_group
}

output "grafana_token_parameter" {
  description = "Where the Grafana Cloud access policy token goes, written by the operator: aws ssm put-parameter --overwrite --type SecureString --name <this> --value <token>. Empty without grafana_cloud."
  value       = module.controlplane.grafana_token_parameter
}

output "controlplane" {
  description = "Everything modules/controlplane outputs."
  value       = module.controlplane
}

output "runners" {
  description = "Everything modules/runners outputs."
  value       = module.runners
}
