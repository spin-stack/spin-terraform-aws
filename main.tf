# A Spinbox installation on AWS: the control plane with its database, proxy and network
# (modules/controlplane), the runners' group it sizes (modules/runners), and the browser terminal
# the dashboard opens a workspace in (modules/terminal). What an installation usually decides is a
# variable here; everything else is each module's, used directly where it matters - the three are
# this composed and nothing more.
#
# Every variable here but the three required ones defaults to null, which each module reads as
# its own default: the defaults are said once, where they mean something.

module "controlplane" {
  source = "./modules/controlplane"

  name                = var.name
  spin_version        = var.spin_version
  domain              = var.domain
  acme_email          = var.acme_email
  admin_email         = var.admin_email
  runner_policy       = var.runner_policy
  proxy_allowed_cidrs = var.proxy_allowed_cidrs
  instance_type       = var.instance_type
  proxy_instance_type = var.proxy_instance_type
  collector           = var.collector
  root_volume_gb      = var.controlplane_volume_gb
  image_ids           = var.image_ids
  image_measurements  = var.image_measurements
  installation_config = var.installation_config
  runner_idle_minutes = var.runner_idle_minutes
  quiet_hours         = var.quiet_hours
  time_zone           = var.time_zone
  decommission        = var.decommission
  monthly_budget_usd  = var.monthly_budget_usd
  budget_emails       = var.budget_emails
  tags                = var.tags
}

module "runners" {
  source = "./modules/runners"

  controlplane   = module.controlplane
  instance_types = var.runner_instance_types
  vcpus          = var.runner_vcpus
  spot           = var.runner_spot
  max_hosts      = var.max_runners
  rollout        = var.runner_rollout
  request_quota  = var.request_quota
  data_volume_gb = var.runner_data_volume_gb
  root_volume_gb = var.runner_root_volume_gb
  tags           = var.tags
}

# term.<domain>. Its files are a spin release's, checked by `task term:fetch` before they are here:
# OpenTofu can neither check a signature nor unpack the tarball. The module refuses a directory
# that is not spin_version's, so an apply cannot publish one release's terminal for another.
module "terminal" {
  source    = "./modules/terminal"
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }

  name     = module.controlplane.name
  iam_name = module.controlplane.iam_name
  domain   = var.domain
  zone_id  = module.controlplane.public_zone_id
  release  = var.spin_version
  files    = coalesce(var.terminal_files, "${path.root}/term")
  tags     = var.tags
}
