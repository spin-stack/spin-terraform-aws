variable "name" {
  description = "Prefix for every resource: the control plane module's name."
  type        = string
  default     = "spin"
}

variable "spin_version" {
  description = "The release a new runner installs. Its spin-install fetches the runner from the control plane and refuses one of another release, so this is the control plane's; a host updates itself from there on."
  type        = string
  validation {
    condition     = can(regex("^v[0-9]{8}\\.[0-9]+$", var.spin_version))
    error_message = "spin_version is a dated release, v<YYYYMMDD>.<N>."
  }
}

variable "controlplane" {
  description = "The control plane module's outputs, as they are: where the runners go, whom they dial, and where they read the token and CA."
  type = object({
    vpc_id              = string
    subnet_ids          = list(string)
    security_group_id   = string
    url                 = string
    token_parameter     = string
    token_parameter_arn = string
    ca_parameter        = string
    ca_parameter_arn    = string
    unpublished         = string
    boundary_arn        = string
    domain              = string
    proxy_private_ip    = string
  })
}

variable "instance_types" {
  description = <<-EOT
    What the group may start, most preferred first. Keep them one CPU generation: a checkpoint
    records the processor and its flags as -cpu host showed them (MachineIdentity in
    internal/runner/vmm), and resumes only onto a host that shows the same — a workspace
    suspended at night on one family and brought back on another cold-boots. Nested
    virtualization is offered on C8i, M8i, R8i (and their d variants), C7i, M7i, R7i and I7i; a
    d variant brings the local NVMe the runner's data goes on.
  EOT
  type        = list(string)
  default     = ["m8id.8xlarge", "m8id.12xlarge"]
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types names at least one."
  }
}

variable "nested_virtualization" {
  description = "Enable KVM inside the instance. False for .metal types, which have it by being metal and refuse the option."
  type        = bool
  default     = true
}

variable "spot" {
  description = "Every host a spot instance. The pool token's policy is what tells each one a stop is a reclaim."
  type        = bool
  default     = true
}

variable "max_hosts" {
  description = "The most runners the group may have. How many it has is the control plane's to decide: none until a workspace waits for a host, and none again once nothing has run for the control plane module's runner_idle_minutes."
  type        = number
  default     = 1
  validation {
    condition     = var.max_hosts >= 1
    error_message = "max_hosts is at least one; a group that may have none is one no workspace can wait for."
  }
}

variable "drain_seconds" {
  description = "How long a host the group is taking away is held while it empties itself: the termination hook's timeout. At least the pool token's --shutdown-grace; the hook is left to expire, so this is also how long each scale-in takes."
  type        = number
  default     = 150
  validation {
    condition     = var.drain_seconds >= 30 && var.drain_seconds <= 7200
    error_message = "drain_seconds is between 30 and 7200, the hook's own bounds."
  }
}

variable "data_volume_gb" {
  description = "An EBS volume for the runner's data, for an instance type with no local NVMe. Zero uses the instance store, which is the right disk for volumes' cache and costs nothing more."
  type        = number
  default     = 0
}

variable "root_volume_gb" {
  type    = number
  default = 30
}

variable "session_manager" {
  description = "Let Session Manager reach the hosts. There is no SSH either way."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
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
