# A spin installation on AWS: the control plane with its catalog, proxy and network
# (modules/controlplane), and the runners' group it sizes (modules/runners). What an installation
# usually decides is a variable here; everything else is each module's, used directly where it
# matters - the two are this composed and nothing more.
#
# Every variable here but the three required ones defaults to null, which each module reads as
# its own default: the defaults are said once, where they mean something.

module "controlplane" {
  source = "./modules/controlplane"

  name                = var.name
  spin_version        = var.spin_version
  spin_boot_sha256    = var.spin_boot_sha256
  domain              = var.domain
  acme_email          = var.acme_email
  admin_email         = var.admin_email
  runner_policy       = var.runner_policy
  proxy_allowed_cidrs = var.proxy_allowed_cidrs
  instance_type       = var.instance_type
  proxy_instance_type = var.proxy_instance_type
  database            = var.database
  collector           = var.collector
  installation_config = var.installation_config
  runner_idle_minutes = var.runner_idle_minutes
  quiet_hours         = var.quiet_hours
  time_zone           = var.time_zone
  tags                = var.tags
}

module "runners" {
  source = "./modules/runners"

  controlplane   = module.controlplane
  instance_types = var.runner_instance_types
  spot           = var.runner_spot
  max_hosts      = var.max_runners
  request_quota  = var.request_quota
  data_volume_gb = var.runner_data_volume_gb
  root_volume_gb = var.runner_root_volume_gb
  tags           = var.tags
}
