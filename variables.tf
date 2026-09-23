variable "spin_version" {
  description = "The release to install, as v<YYYYMMDD>.<N>: the control plane's and the proxy's. A runner installs whichever release its control plane serves."
  type        = string
}

variable "spin_boot_sha256" {
  description = <<-EOT
    The SHA-256 of spin-boot-linux-amd64 of spin_version, from that release's checksums.txt: the
    one file a machine fetches before anything is verified, and so the one thing to pin here.
    Everything after it — the release's tarballs and their signatures — spin-boot checks itself
    against the signature spin's release workflow published.
  EOT
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

variable "admin_email" {
  description = "Who the first administrator signs in as; none is admin@<domain>."
  type        = string
  default     = null
}

variable "runner_policy" {
  description = "The host policy a runner starts with when it joins: shutdown_grace and preemption_source; modules/controlplane's default is a spot runner on AWS with 100s."
  type = object({
    shutdown_grace    = optional(string)
    preemption_source = optional(string)
  })
  default = null
}

variable "proxy_allowed_cidrs" {
  description = "Where users reach the proxy on 443 from; modules/controlplane's default is anywhere."
  type        = list(string)
  default     = null
}

variable "instance_type" {
  description = "The control plane's machine; modules/controlplane's default is t8i.micro."
  type        = string
  default     = null
}

variable "proxy_instance_type" {
  description = "The proxy's machine; modules/controlplane's default is t8i.micro."
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
  description = "The installation's config file (spin's configs/spin-example.yaml), as YAML: the control plane makes its catalog match it at every start."
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

variable "runner_data_volume_gb" {
  description = "An EBS volume for each runner's data, for instance types with no local NVMe (none of sa-east-1's with nested virtualization have one). modules/runners' default, 0, uses the instance store."
  type        = number
  default     = null
}

variable "runner_root_volume_gb" {
  description = "Each runner's root disk: the OS and the machine's files. modules/runners' default is 30."
  type        = number
  default     = null
}

variable "request_quota" {
  description = "Ask AWS for the vCPU quota max_runners runners need when the account's is lower; modules/runners' default is true."
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
