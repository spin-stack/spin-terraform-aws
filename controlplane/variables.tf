variable "name" {
  description = "Prefix for every resource, and the SSM path (/<name>/...) the runners read their token and CA from."
  type        = string
  default     = "spin"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name is lowercase letters, digits and dashes, starting with a letter: it names a bucket and an SSM path."
  }
}

variable "spin_version" {
  description = "The release to install, as v<YYYYMMDD>.<N>. Runners are fetched from the control plane, so this is the fleet's release."
  type        = string
  validation {
    condition     = can(regex("^v[0-9]{8}\\.[0-9]+$", var.spin_version))
    error_message = "spin_version is a dated release, v<YYYYMMDD>.<N>."
  }
}

variable "domain" {
  description = "The base domain: the dashboard is app.<domain>, workspaces are *.app.<domain>."
  type        = string
}

variable "acme_email" {
  description = "The address Let's Encrypt writes to; empty is admin@<domain>."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "A hosted zone to write app.<domain> and *.app.<domain> into. Empty writes nothing, and the records are yours to point at the elastic_ip output."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "The VPC's range. One /20 public subnet per availability zone is carved from it."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "How many zones to make subnets in. The control plane uses the first; runners spread across all, which is what gives a spot group somewhere to go when one zone runs out."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "The control plane's machine. It is Postgres, the control plane and the proxy under Compose, and nothing that runs a workspace."
  type        = string
  default     = "t3.medium"
}

variable "data_volume_gb" {
  description = "The volume /etc/spin-stack and /var/lib/spin-stack live on: the database, the encryption key and the CA. It outlives the instance."
  type        = number
  default     = 50
}

variable "snapshot_retention_days" {
  description = "Daily snapshots of the data volume kept. Beside them the control plane writes a backup of the catalog into the bucket every hour."
  type        = number
  default     = 7
}

variable "object_lock_days" {
  description = "The bucket's default Object Lock retention, in GOVERNANCE mode. A deleted object's bytes last this long, and spin's lifecycle rule waits it out."
  type        = number
  default     = 30
}

variable "pool_token_flags" {
  description = "The host policy every runner the pool's token registers starts with, as `controlplane registration-token` flags. Say a little less grace than the two minutes a spot reclaim gives."
  type        = list(string)
  default     = ["--preemption-source", "aws", "--shutdown-grace", "100s"]
}

variable "pool_token_rotation" {
  description = "How often the control plane mints a new pool token into SSM, as a systemd OnCalendar/OnUnitActiveSec span. Each token lasts four times this, so one published is good for three rotations after it."
  type        = string
  default     = "6h"
  validation {
    condition     = can(regex("^[0-9]+h$", var.pool_token_rotation))
    error_message = "pool_token_rotation is a whole number of hours, e.g. 6h."
  }
}

variable "installation_config" {
  description = <<-EOT
    The installation's config file (configs/spin-example.yaml), as YAML. This module applies it
    on the control plane's first boot with the autoscaling settings below added to its settings
    block, and is then its one author: a second file applied from elsewhere would remove what
    this one declares, and this one what it does.
  EOT
  type        = string
  default     = ""
}

variable "runner_idle_minutes" {
  description = "How long the fleet has no workspace running, starting or waiting before the runners' group is emptied."
  type        = number
  default     = 60
  validation {
    condition     = var.runner_idle_minutes >= 1
    error_message = "runner_idle_minutes is at least one."
  }
}

variable "quiet_hours" {
  description = "HH:MM-HH:MM in time_zone when an idle fleet is emptied at once rather than after runner_idle_minutes. A workspace asked for then still brings a runner up. Empty is none."
  type        = string
  default     = ""
}

variable "time_zone" {
  description = "The IANA zone quiet_hours are in."
  type        = string
  default     = "UTC"
}

variable "tags" {
  description = "Tags on everything this module creates."
  type        = map(string)
  default     = {}
}

variable "ubuntu_release" {
  description = "The Ubuntu release the machines boot, as YY.MM; the newest image of it Canonical publishes is used. 26.04 is the LTS with a 7.x kernel."
  type        = string
  default     = "26.04"
  validation {
    condition     = can(regex("^[0-9]{2}\\.(04|10)$", var.ubuntu_release))
    error_message = "ubuntu_release is a release number, e.g. 26.04."
  }
}
