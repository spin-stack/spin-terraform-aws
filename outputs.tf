# What an operator has after an apply, and what they do with it. An installation nobody can sign
# in to is an installation that is not up, so the way in comes first and comes with its own
# commands: /login offers the identity providers there are, and a new installation has none.
locals {
  aws = "aws --region ${module.controlplane.region}"

  sign_in = {
    url  = "https://app.${var.domain}"
    user = module.controlplane.admin_email
    password = join(" ", ["${local.aws} ssm get-parameter --with-decryption --name",
    module.controlplane.admin_password_parameter, "--query Parameter.Value --output text"])
  }

  # Whether a group's machine is in service, and if it is not, what the group last did and why.
  status = "${local.aws} autoscaling describe-auto-scaling-groups --auto-scaling-group-names %s --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState]' --output text"
  why    = "${local.aws} autoscaling describe-scaling-activities --auto-scaling-group-name %s --max-items 3 --query 'Activities[].[StatusCode,StatusMessage]' --output text"
  # A machine is reached through Session Manager - no port 22 and no key - and the one to reach is
  # the one in service, not whichever the group lists first.
  session = "${local.aws} ssm start-session --target $(${local.aws} autoscaling describe-auto-scaling-groups --auto-scaling-group-names %s --query \"AutoScalingGroups[0].Instances[?LifecycleState=='InService'] | [0].InstanceId\" --output text)"
  # What each machine's boot said, kept after the machine is gone: a role's machines are a stream
  # prefix (spin's boot names a stream <role>/<step>/<instance>), so one role is read without an
  # instance to look up, and --follow keeps reading as the next one boots.
  boot_log_of = "${local.aws} logs tail ${module.controlplane.boot_log_group} --log-stream-name-prefix %s/ --since 1h --follow"
  boot_log = {
    for role in ["control-plane", "proxy", "runner"] : role => format(local.boot_log_of, role)
  }

  next_steps = join("\n", concat(
    [
      "1. DNS: ${var.domain}'s zone is this installation's, in Route 53. Where the domain is",
      "   registered - or in its parent's zone, for a subdomain - set its nameservers to:",
      "     ${join(" ", module.controlplane.name_servers)}",
      "   When this answers ${module.controlplane.proxy_ip}, they are there:",
      "     dig +short app.${var.domain}",
      "   The proxy gets its certificate a few minutes after that.",
      "",
      "2. Wait for the installation to come up: about ten minutes the first time. Each machine",
      "   says InService when it is ready:",
      "     ${format(local.status, module.controlplane.controlplane_group)}",
      "     ${format(local.status, module.controlplane.proxy_group)}",
      "   If one is not, what went wrong is in its boot's log, and in what its group last did:",
      "     ${local.boot_log["control-plane"]}",
      "     ${local.boot_log["proxy"]}",
      "     ${format(local.why, module.controlplane.controlplane_group)}",
      "",
      "3. Sign in at ${local.sign_in.url} as ${local.sign_in.user}, with the one-time password:",
      "     ${local.sign_in.password}",
      "   The first page asks you for a password of your own.",
      "",
      "4. The runners start at zero: the first workspace you create starts one, which takes a few",
      "   minutes, and the group is emptied after ${module.controlplane.runner_idle_minutes} idle minutes${var.quiet_hours == null ? "" : " (or at once during ${var.quiet_hours} ${coalesce(var.time_zone, "UTC")})"}.",
      "     ${format(local.status, module.runners.autoscaling_group)}",
      "",
      "5. A shell on a machine, when you need one:",
      "     ${format(local.session, module.controlplane.controlplane_group)}",
    ],
    [
      "",
      "6. The installation keeps its own logs, traces and metrics on the control plane's machine,",
      "   over the logs bucket. Its dashboards are under Observe -> Metrics, for administrators;",
      "   what is kept is Admin -> Settings -> Telemetry.",
    ],
  ))
}

# Read as prose: `tofu output -raw next_steps`.
output "next_steps" {
  description = "What to do now that the apply is done, in order: DNS, the first sign-in, what the runners do, and how to reach a machine. Read it with `tofu output -raw next_steps`."
  value       = local.next_steps
  # Nothing in it is a secret. Marked so that no plan prints it - a destroy's listed it as an
  # output going away, forty lines of what to do next under a plan that removes everything - and
  # it is read when it is wanted, with -raw, which prints it as it is.
  sensitive = true
}

output "dashboard" {
  description = "The installation's dashboard."
  value       = "https://app.${var.domain}"
}

output "first_sign_in" {
  description = "The setup page, the first administrator, and the command that reads their one-time password: an SSM SecureString this apply wrote without it ever being in the state."
  value       = local.sign_in
}

output "name_servers" {
  description = "The domain's zone's nameservers: what its registrar, or its parent's zone, points at."
  value       = module.controlplane.name_servers
}

output "proxy_ip" {
  description = "The proxy's elastic IP, where app.<domain>, tunnel.app.<domain> and *.ws.<domain> point: the one address of the installation the internet reaches."
  value       = module.controlplane.proxy_ip
}

output "controlplane_group" {
  description = "The control plane's group of one; its machine is reached with `aws ssm start-session --target <instance>`."
  value       = module.controlplane.controlplane_group
}

output "update_status" {
  description = "After an apply that changed a machine: how its replacement went. Successful, InProgress, or RollbackSuccessful with the reason - in which case the old machine is still serving."
  value = {
    for g in [module.controlplane.controlplane_group, module.controlplane.proxy_group] :
    g => "${local.aws} autoscaling describe-instance-refreshes --auto-scaling-group-name ${g} --max-records 1 --query 'InstanceRefreshes[0].[Status,StatusReason,PercentageComplete]' --output text"
  }
}

# The group keeps its old launch template until a refresh succeeds, so a machine launched from any
# other is the refresh's. It waits on the launch hook until its heartbeat times out; abandoning it
# ends that wait now, and the rollback, asked for first, keeps the refresh from launching another.
output "update_abort" {
  description = "After an apply whose new machine will not come up: the command that stops waiting for it - rolls the refresh back and abandons the launch the hook still holds - so the next apply can change the group (task update:abort)."
  value = {
    for g in [module.controlplane.controlplane_group, module.controlplane.proxy_group] :
    g => join(" ", [
      "v=$(${local.aws} autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${g} --query 'AutoScalingGroups[0].LaunchTemplate.Version' --output text);",
      "${local.aws} autoscaling rollback-instance-refresh --auto-scaling-group-name ${g};",
      "for i in $(${local.aws} autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${g} --query \"AutoScalingGroups[0].Instances[?LifecycleState=='Pending:Wait' && LaunchTemplate.Version!='$v'].InstanceId\" --output text);",
      "do ${local.aws} autoscaling complete-lifecycle-action --auto-scaling-group-name ${g} --lifecycle-hook-name ready --lifecycle-action-result ABANDON --instance-id $i; done",
    ])
  }
}

output "boot_log" {
  description = "By role, the command that reads what its machines' boots said - the ones that are gone included - and follows the next one's."
  value       = local.boot_log
}

output "runners_group" {
  description = "The runners' group, which the control plane sizes: empty until a workspace waits for one."
  value       = module.runners.autoscaling_group
}

output "controlplane" {
  description = "Everything modules/controlplane outputs."
  value       = module.controlplane
}

output "runners" {
  description = "Everything modules/runners outputs."
  value       = module.runners
}
