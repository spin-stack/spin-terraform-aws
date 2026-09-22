# What an operator has after an apply, and what they do with it. An installation nobody can sign
# in to is an installation that is not up, so the way in comes first and comes with its own
# commands: /login offers the identity providers there are, and a new installation has none.
locals {
  sign_in = {
    url  = "https://app.${var.domain}/setup"
    user = "aws --region ${module.controlplane.region} ssm get-parameter --name ${module.controlplane.bootstrap_user_parameter} --query Parameter.Value --output text"
    password = join(" ", ["aws --region ${module.controlplane.region} ssm get-parameter --with-decryption --name",
    module.controlplane.bootstrap_password_parameter, "--query Parameter.Value --output text"])
  }

  # The machines of an installation are reached through Session Manager: no port 22 and no key.
  session = "aws --region ${module.controlplane.region} ssm start-session --target $(aws --region ${module.controlplane.region} autoscaling describe-auto-scaling-groups --auto-scaling-group-names %s --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"

  next_steps = join("\n", concat(
    var.route53_zone_id == null ? [
      "1. DNS, which is yours: point app.${var.domain} and *.app.${var.domain} at ${module.controlplane.proxy_ip} (A records).",
      "   The proxy answers on 80 for the ACME challenge, so its certificate arrives once those resolve.",
      ] : [
      "1. DNS: app.${var.domain} and *.app.${var.domain} are written into the zone you gave.",
    ],
    [
      "",
      "2. Sign in at ${local.sign_in.url} - not /login, which offers identity providers and this",
      "   installation has none yet. The first administrator and their one-time password:",
      "     ${local.sign_in.user}",
      "     ${local.sign_in.password}",
      "   In the setup page: set a password of your own, configure GitHub OAuth if you want one,",
      "   and then disable this administrator.",
      "",
      "3. The runners are a fleet that starts at zero: the control plane starts one when a workspace",
      "   waits for it, and empties the group after ${module.controlplane.runner_idle_minutes} idle minutes${var.quiet_hours == null ? "" : " (or at once during ${var.quiet_hours} ${coalesce(var.time_zone, "UTC")})"}.",
      "   A first workspace therefore takes a machine's boot longer than the next one.",
      "     aws --region ${module.controlplane.region} autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${module.runners.autoscaling_group} --query 'AutoScalingGroups[0].[DesiredCapacity,length(Instances)]'",
      "",
      "4. The machines, when a boot needs reading: /var/log/spin-bootstrap.log, and the units",
      "   spin-controlplane, spin-proxy and spin-runner.",
      "     ${format(local.session, module.controlplane.controlplane_group)}",
      "     ${format(local.session, module.controlplane.proxy_group)}",
    ],
    module.controlplane.grafana_token_parameter == "" ? [] : [
      "",
      "5. Telemetry: the collector ships nothing until the token is there, which is yours to write:",
      "     aws --region ${module.controlplane.region} ssm put-parameter --overwrite --type SecureString --name ${module.controlplane.grafana_token_parameter} --value <token>",
    ],
  ))
}

# Read as prose: `tofu output -raw next_steps`.
output "next_steps" {
  description = "What to do now that the apply is done, in order: DNS, the first sign-in, what the runners do, and how to reach a machine. Read it with `tofu output -raw next_steps`."
  value       = local.next_steps
}

output "dashboard" {
  description = "The installation's dashboard."
  value       = "https://app.${var.domain}"
}

output "first_sign_in" {
  description = "The setup page and the two commands that read the first administrator: the password is an SSM SecureString the control plane wrote, never Terraform's to hold."
  value       = local.sign_in
}

output "proxy_ip" {
  description = "The proxy's elastic IP, where app.<domain> and *.app.<domain> point: the one address of the installation the internet reaches."
  value       = module.controlplane.proxy_ip
}

output "controlplane_group" {
  description = "The control plane's group of one; its machine is reached with `aws ssm start-session --target <instance>`."
  value       = module.controlplane.controlplane_group
}

output "runners_group" {
  description = "The runners' group, which the control plane sizes: empty until a workspace waits for one."
  value       = module.runners.autoscaling_group
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
