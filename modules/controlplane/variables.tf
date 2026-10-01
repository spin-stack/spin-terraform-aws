# Every variable with a default is nullable = false: null is "the default", so a module that wraps
# this one - the repository's root - passes what it was given without restating what it means.

variable "name" {
  description = "The installation's name, one per region of an account: every resource's prefix, the SSM path (/spin/<name>/...) each machine's document is at, and - with the region - every IAM name. Two installations of one account may share a name in two regions, and not in one (claim.tf)."
  type        = string
  default     = "spin"
  nullable    = false
  # Twenty-six at most: the longest name made of it is a bucket, "<name>-database-<account>-<region>",
  # and a bucket's is 63 characters with a region of 14 (ap-southeast-4). No dash at either end and
  # none doubled, as a bucket's name may not have them.
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 26 && can(regex("^[a-z](-?[a-z0-9])*$", var.name))
    error_message = "name is 2 to 26 lowercase letters, digits and single dashes, starting with a letter and not ending with a dash: it names buckets, IAM roles and an SSM path."
  }
}

variable "spin_version" {
  description = "The release the installation runs, as v<YYYYMMDD>.<N>: every machine boots the Spin OS image of it (spin-stack/ami), published into this account and tagged spin:version."
  type        = string
  validation {
    condition     = can(regex("^v[0-9]{8}\\.[0-9]+$", var.spin_version))
    error_message = "spin_version is a dated release, v<YYYYMMDD>.<N>."
  }
}

variable "domain" {
  description = "The base domain: the dashboard is app.<domain>, workspaces are *.ws.<domain>."
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
  description = "The VPC's range, a /16. One /20 public subnet per availability zone is carved from its first half, and one /24 for the proxy per zone from x.x.136.0 on."
  type        = string
  default     = "10.42.0.0/16"
  nullable    = false
  # The subnets are carved at fixed offsets (network.tf, proxy.tf): from a /16 they never overlap
  # and all fit; from anything else they overlap, or fall outside it.
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr is an IPv4 /16, e.g. 10.42.0.0/16."
  }
}

variable "availability_zones" {
  description = "How many zones to make subnets in. The control plane, the proxy and the runners may each be started in any of them, which is what gives a group somewhere to go when a zone runs out."
  type        = number
  default     = 3
  nullable    = false
  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 8
    error_message = "availability_zones is 2 to 8: a spot group needs a second zone to go to when one runs out, and the VPC's range has room for eight."
  }
}

variable "instance_type" {
  description = "The control plane's machine: the control plane, its database (PostgreSQL), the collector, and the stores of logs, traces and metrics it runs."
  type        = string
  default     = "t8i.medium"
  nullable    = false
}

variable "root_volume_gb" {
  description = "The control plane's disk: beside the read-only OS, /var takes the rest - the database, the logs' and metrics' stores and their caches. A new size is a new machine, replaced beside the old."
  type        = number
  default     = 40
  nullable    = false
  validation {
    condition     = var.root_volume_gb >= 20
    error_message = "root_volume_gb is at least 20: the OS alone takes some of it."
  }
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
  description = "Keep the VPC resolver's query log in CloudWatch: every name looked up, a workspace's included. It is Route 53 Resolver's, and off unless asked for. Each installation that turns it on takes one of the ten CloudWatch Logs resource policies a region of an account may have."
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

variable "decommission" {
  description = "Set to true, and applied, before destroying the installation: its buckets lose the policies that refuse every object write from outside the VPC - the destroy runs from outside it - and a destroy empties every bucket, data included, lifting legal holds and bypassing the GOVERNANCE retention. Never set on an installation that is to keep its data."
  type        = bool
  default     = false
  nullable    = false
}

variable "object_lock_days" {
  description = "The bucket's default Object Lock retention, in GOVERNANCE mode. A deleted object's bytes last this long, and the bucket's lifecycle (bucket.tf) removes them a day after."
  type        = number
  default     = 30
  nullable    = false
}

variable "database_lock_days" {
  description = "The database archive's default Object Lock retention, in GOVERNANCE mode: how long what a delete or an overwrite left there can still be restored. The lifecycle removes it a day after (database_bucket.tf)."
  type        = number
  default     = 14
  nullable    = false
  validation {
    condition     = var.database_lock_days >= 1
    error_message = "database_lock_days is at least one."
  }
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
    it where the control plane reads it at every start, which seeds the database from it before
    it serves. What the file later says differently is shown in the dashboard to apply or
    dismiss, and nothing is written over what an administrator decided.
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

variable "image_ids" {
  description = "Spin OS AMIs of your own, one per role - control-plane, runner and proxy - instead of those images.json names for spin_version in this region. Each must carry that release, laid for that role: a machine refuses a document of another release, and an image laid for another role."
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition = length(var.image_ids) == 0 || (
      toset(keys(var.image_ids)) == toset(["control-plane", "runner", "proxy"]) &&
      alltrue([for id in values(var.image_ids) : can(regex("^ami-[0-9a-f]{17}$", id))])
    )
    error_message = "image_ids names an AMI for each of control-plane, runner and proxy, or none."
  }
}

variable "monthly_budget_usd" {
  description = "What the installation may cost in a month, in US dollars: an AWS Budget on its spin:installation tag (budget.tf), which the control plane reads and alerts reach. Null is no budget."
  type        = number
  default     = null
  validation {
    condition     = var.monthly_budget_usd == null ? true : var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd is an amount above zero, or null for none."
  }
}

variable "budget_emails" {
  description = "Who AWS emails when the month's cost passes 80 % or 100 % of monthly_budget_usd, or is forecast to pass it."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "image_measurements" {
  description = "The PCRs an instance of each role's image measures - its manifest's measurements, SHA384 in lowercase hex - by role, control-plane, runner and proxy, instead of measurements.json's: the control plane's key is answered to the control plane's (attested_key.tf), a host joins only as the runner's, and the proxy is given its token only as the proxy's (host_attestation). Required with image_ids, and for a release published before its PCRs were."
  type        = map(object({ pcr4 = string, pcr7 = string, pcr12 = string }))
  default     = null
  validation {
    condition = var.image_measurements == null ? true : (
      toset(keys(var.image_measurements)) == toset(["control-plane", "runner", "proxy"]) &&
      alltrue([for role in values(var.image_measurements) : alltrue([for pcr in values(role) : can(regex("^[0-9a-f]{96}$", pcr))])])
    )
    error_message = "image_measurements are the control-plane's, the runner's and the proxy's, each three SHA384 digests: 96 lowercase hex digits, as NitroTPM reports them."
  }
}
