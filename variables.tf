variable "spin_version" {
  description = "The release the installation runs, as v<YYYYMMDD>.<N>: every machine boots the Spin OS image of it (spin-stack/ami), published into this account and tagged spin:version."
  type        = string
}

variable "domain" {
  description = "The base domain: the dashboard is app.<domain>, workspaces are *.ws.<domain>."
  type        = string
}

variable "name" {
  description = "The installation's name, one per region of an account (two regions may share it): every resource's prefix, the SSM path /spin/<name>/, and with the region every IAM name. 2 to 26 characters; modules/controlplane's default is spin."
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
  description = "The control plane's machine; modules/controlplane's default is t8i.medium."
  type        = string
  default     = null
}

variable "proxy_instance_type" {
  description = "The proxy's machine; modules/controlplane's default is t8i.micro."
  type        = string
  default     = null
}

variable "collector" {
  description = "The collector, as modules/controlplane's collector object: how often metrics are pushed to it; modules/controlplane's default is 60s. Where it sends is set in the dashboard."
  type = object({
    metric_interval = optional(string)
  })
  default = null
}

variable "controlplane_volume_gb" {
  description = "The control plane's disk, which /var - the database and the stores - takes all of past the OS; modules/controlplane's default is 40."
  type        = number
  default     = null
}

variable "image_id" {
  description = "A Spin OS AMI of your own for every machine, instead of the one images.json names for spin_version in this region."
  type        = string
  default     = null
}

variable "installation_config" {
  description = "The installation's config file (spin's configs/spin-example.yaml), as YAML: the control plane seeds its database from it at start, and shows a later change to it in the dashboard to apply or dismiss."
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

variable "decommission" {
  description = "Set to true and apply before `tofu destroy`: the buckets lose their VPC-only policies and a destroy empties them, data included (README.md, \"Removing an installation\"). modules/controlplane's default is false."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Tags on everything both modules create."
  type        = map(string)
  default     = null
}
