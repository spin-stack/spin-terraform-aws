variable "spin_version" {
  description = "The release to install, as v<YYYYMMDD>.<N>: the control plane's and the proxy's. A runner installs whichever release its control plane serves."
  type        = string
}

variable "domain" {
  description = "The base domain: the dashboard is app.<domain>, workspaces are *.app.<domain>."
  type        = string
}

variable "name" {
  description = "Prefix for every resource and the SSM path; modules/controlplane's default is spin."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "A public hosted zone to write app.<domain> and *.app.<domain> into; none writes nothing, and the records are yours to point at the proxy_ip output."
  type        = string
  default     = null
}

variable "acme_email" {
  description = "The address Let's Encrypt writes to; none is admin@<domain>."
  type        = string
  default     = null
}

variable "proxy_allowed_cidrs" {
  description = "Where users reach the proxy on 443 from; modules/controlplane's default is anywhere."
  type        = list(string)
  default     = null
}

variable "instance_type" {
  description = "The control plane's machine; modules/controlplane's default is t3.micro."
  type        = string
  default     = null
}

variable "proxy_instance_type" {
  description = "The proxy's machine; modules/controlplane's default is t3.micro."
  type        = string
  default     = null
}

variable "database" {
  description = "The catalog's RDS instance, as modules/controlplane's database object: engine_version, instance_class, storage_gb, max_storage_gb, multi_az, backup_retention_days, deletion_protection."
  type        = any
  default     = null
}

variable "grafana_cloud" {
  description = "Where the installation ships its telemetry, as modules/controlplane's grafana_cloud object; none ships nothing."
  type        = any
  default     = null
}

variable "installation_config" {
  description = "The installation's config file (spin's configs/spin-example.yaml), as YAML, applied on the control plane's first boot."
  type        = string
  default     = null
}

variable "runner_idle_minutes" {
  description = "How long the fleet is idle before its runners' group is emptied; modules/controlplane's default is 60."
  type        = number
  default     = null
}

variable "quiet_hours" {
  description = "HH:MM-HH:MM in time_zone when an idle fleet is emptied at once; none is none."
  type        = string
  default     = null
}

variable "time_zone" {
  description = "The IANA zone quiet_hours are in; modules/controlplane's default is UTC."
  type        = string
  default     = null
}

variable "runner_instance_types" {
  description = "What the runners' group may start, most preferred first, one CPU generation; see modules/runners."
  type        = list(string)
  default     = null
}

variable "runner_spot" {
  description = "Every runner a spot instance; modules/runners' default is true."
  type        = bool
  default     = null
}

variable "max_runners" {
  description = "The most runners the group may have; the control plane decides how many it has. modules/runners' default is 1."
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags on everything both modules create."
  type        = map(string)
  default     = null
}
