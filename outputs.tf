output "dashboard" {
  description = "The installation's dashboard."
  value       = "https://app.${var.domain}"
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
