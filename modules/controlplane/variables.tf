# Every variable with a default is nullable = false: null is "the default", so a module that wraps
# this one - the repository's root - passes what it was given without restating what it means.

variable "name" {
  description = "Prefix for every resource, and the SSM path (/<name>/...) each machine's document is at."
  type        = string
  default     = "spin"
  nullable    = false
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

variable "internal_zone" {
  description = "The private zone the components reach each other by: cp.<this> and proxy.<this>, resolved only inside the VPC."
  type        = string
  default     = "spin.internal"
  nullable    = false
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.internal_zone))
    error_message = "internal_zone is a DNS name in lower case, e.g. spin.internal."
  }
}

variable "acme_email" {
  description = "The address Let's Encrypt writes to; empty is admin@<domain>."
  type        = string
  default     = ""
  nullable    = false
}

variable "vpc_cidr" {
  description = "The VPC's range. One /20 public subnet per availability zone is carved from it."
  type        = string
  default     = "10.42.0.0/16"
  nullable    = false
}

variable "availability_zones" {
  description = "How many zones to make subnets in. The control plane uses the first; runners spread across all, which is what gives a spot group somewhere to go when one zone runs out."
  type        = number
  default     = 3
  nullable    = false
  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 8
    error_message = "availability_zones is 2 to 8: RDS takes a subnet in two zones at least, and the VPC's range has room for eight."
  }
}

variable "instance_type" {
  description = "The control plane's machine: the control plane, the collector, and the store of logs and traces it runs (Quickwit). Its database is RDS; the store is what sizes it."
  type        = string
  default     = "t8i.small"
  nullable    = false
}

variable "database" {
  description = <<-EOT
    The database's RDS instance. db.t4g.micro and 20 GB are the free tier's where the account has
    one; the database is rows about workspaces and volumes, not their data, which is the bucket's.
    deletion_protection keeps a destroy from taking it: turn it off, apply, then destroy.
    apply_immediately makes a change to the instance - its class, its version - during the apply
    that asks for it, a minute or two of the database restarting; false leaves it for RDS's
    maintenance window.
    insights keeps seven days of Performance Insights: which statements take the time, and what
    they wait on.
  EOT
  type = object({
    engine_version        = optional(string, "18")
    instance_class        = optional(string, "db.t4g.micro")
    storage_gb            = optional(number, 20)
    max_storage_gb        = optional(number, 100)
    multi_az              = optional(bool, false)
    backup_retention_days = optional(number, 7)
    deletion_protection   = optional(bool, true)
    apply_immediately     = optional(bool, true)
    insights              = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "admin_email" {
  description = "Who the first administrator signs in as; empty is admin@<domain>. The one-time password is in the admin_password_parameter output's parameter."
  type        = string
  default     = ""
  nullable    = false
}

variable "flow_logs" {
  description = "Keep the VPC's flow log in CloudWatch: every connection a security group accepted or refused. At a few hosts it is cents a month; a fleet whose workspaces move a lot of data pays about $0.50 a GB of flow records."
  type        = bool
  default     = true
  nullable    = false
}

variable "dns_query_logs" {
  description = "Keep the VPC resolver's query log in CloudWatch: every name looked up, a workspace's included. It is Route 53 Resolver's, and off unless asked for."
  type        = bool
  default     = false
  nullable    = false
}

variable "log_retention_days" {
  description = "How long the flow and query logs are kept."
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days is one of the retentions CloudWatch has: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, ..."
  }
}

variable "proxy_allowed_cidrs" {
  description = "Where users may reach the proxy on 443 from: the dashboard, workspaces and SSH. Anywhere by default; an office's or a VPN's ranges close the installation to everyone else. The runners reach it from inside the VPC whatever this says, and 80 stays open for the ACME challenge."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
  validation {
    condition     = length(var.proxy_allowed_cidrs) > 0 && alltrue([for c in var.proxy_allowed_cidrs : can(cidrnetmask(c))])
    error_message = "proxy_allowed_cidrs is at least one IPv4 CIDR."
  }
}

variable "proxy_instance_type" {
  description = "The proxy's machine: Caddy and nothing else, the one address the internet reaches."
  type        = string
  default     = "t8i.micro"
  nullable    = false
}

variable "object_lock_days" {
  description = "The bucket's default Object Lock retention, in GOVERNANCE mode. A deleted object's bytes last this long, and the bucket's lifecycle (bucket.tf) removes them a day after."
  type        = number
  default     = 30
  nullable    = false
}

variable "runner_policy" {
  description = "The host policy a runner starts with when it joins: how long it stays up once told to stop - a little less than the two minutes a spot reclaim gives - and the cloud that announces a reclaim."
  type = object({
    shutdown_grace    = optional(string, "100s")
    preemption_source = optional(string, "aws")
  })
  default  = {}
  nullable = false
  validation {
    condition     = can(regex("^[0-9]+s$", var.runner_policy.shutdown_grace)) && contains(["aws", "gcp", "azure"], var.runner_policy.preemption_source)
    error_message = "runner_policy.shutdown_grace is whole seconds, e.g. 100s, and preemption_source is aws, gcp or azure."
  }
}

variable "installation_config" {
  description = <<-EOT
    The installation's config file (spin's configs/spin-example.yaml), as YAML. This module adds
    what it knows - the domain, who joins as a host, the autoscaling settings below - and writes
    it where the control plane reads it at every start, which makes the database match it before
    it serves. It is then the file's one author: a second one applied from elsewhere would remove
    what this one declares, and this one what it does.
  EOT
  type        = string
  default     = ""
  nullable    = false
}

variable "runner_idle_minutes" {
  description = "How long the fleet has no workspace running, starting or waiting before the runners' group is emptied."
  type        = number
  default     = 60
  nullable    = false
  validation {
    condition     = var.runner_idle_minutes >= 1
    error_message = "runner_idle_minutes is at least one."
  }
}

variable "quiet_hours" {
  description = "HH:MM-HH:MM in time_zone when an idle fleet is emptied at once rather than after runner_idle_minutes. A workspace asked for then still brings a runner up. Empty is none."
  type        = string
  default     = ""
  nullable    = false
}

variable "time_zone" {
  description = "The IANA zone quiet_hours are in."
  type        = string
  default     = "UTC"
  nullable    = false
}

variable "tags" {
  description = "Tags on everything this module creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "image_id" {
  description = "An AMI for the control plane and the proxy, instead of the newest of ubuntu_release at the time spin_version last changed."
  type        = string
  default     = ""
  nullable    = false
}

variable "ubuntu_release" {
  description = "The Ubuntu release the machines boot, as YY.MM; the newest image of it Canonical publishes is used. 26.04 is the LTS with a 7.x kernel."
  type        = string
  default     = "26.04"
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{2}\\.(04|10)$", var.ubuntu_release))
    error_message = "ubuntu_release is a release number, e.g. 26.04."
  }
}

variable "spin_boot_sha256" {
  description = <<-EOT
    The SHA-256 of spin-boot-linux-amd64 of spin_version: the one file a machine fetches before
    anything is verified, and therefore the one thing this module has to pin. Everything after it
    — the release's tarballs, their signatures — spin-boot checks itself against the signature
    spin's release workflow published.

    It is in that release's checksums.txt, beside the file on the release page.
  EOT
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.spin_boot_sha256))
    error_message = "spin_boot_sha256 is 64 hex digits: the SHA-256 of spin-boot-linux-amd64 of this release."
  }
}
