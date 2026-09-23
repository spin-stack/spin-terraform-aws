# Every variable with a default is nullable = false: null is "the default", so a module that wraps
# this one - the repository's root - passes what it was given without restating what it means.
#
# No name of its own: the control plane module's, which its group, role and SSM path are named
# for, and which its role and boundary name in turn. Two names were two things to keep equal.

variable "controlplane" {
  description = "The control plane module's outputs, as they are: its name, where the runners go, their document, and what a runner's machine runs at its first boot."
  type = object({
    name                        = string
    vpc_id                      = string
    subnet_ids                  = list(string)
    security_group_id           = string
    runner_config_parameter_arn = string
    runner_user_data            = string
    boot_log_policy_arn         = string
    standard_vcpus              = number
    boundary_arn                = string
    collector                   = string
    session_manager_policy_arn  = string
  })
}

variable "instance_types" {
  description = <<-EOT
    What the group may start. Keep them one CPU generation: a checkpoint records the processor
    and its flags as -cpu host showed them (MachineIdentity in spin's internal/runner/vmm), and
    resumes only onto a host that shows the same - a workspace suspended at night on one family
    and brought back on another cold-boots. Nested virtualization is offered on C8i, M8i, R8i
    (and their d variants), C7i, M7i, R7i and I7i; a d variant brings the local NVMe the runner's
    data goes on.

    For spot, name several: AWS gives a spot machine from the pools a request can draw on, and
    one type is one pool per zone. m8id.8xlarge alone scored 3 of 10 in us-west-2 and was reclaimed
    within minutes; the five below score 9. How a list scores in a region, before installing:
      aws ec2 get-spot-placement-scores --target-capacity 1 --region-names <region> \
        --instance-types <the types>
  EOT
  type        = list(string)
  default     = ["m8id.8xlarge", "c8id.8xlarge", "r8id.8xlarge", "m8id.12xlarge", "c8id.12xlarge"]
  nullable    = false
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types names at least one."
  }
}

variable "nested_virtualization" {
  description = "Enable KVM inside the instance. False for .metal types, which have it by being metal and refuse the option."
  type        = bool
  default     = true
  nullable    = false
}

variable "spot" {
  description = "Every host a spot instance. The policy a runner joins under (the control plane module's runner_policy) is what tells each one a stop is a reclaim."
  type        = bool
  default     = true
  nullable    = false
}

variable "request_quota" {
  description = "Ask AWS for the vCPU quota max_hosts runners need, when the account's is lower (quota.tf). A request costs nothing and lowers nothing when it is removed."
  type        = bool
  default     = true
  nullable    = false
}

variable "max_hosts" {
  description = "The most runners the group may have. How many it has is the control plane's to decide: none until a workspace waits for a host, and none again once nothing has run for the control plane module's runner_idle_minutes."
  type        = number
  default     = 1
  nullable    = false
  validation {
    condition     = var.max_hosts >= 1
    error_message = "max_hosts is at least one; a group that may have none is one no workspace can wait for."
  }
}

variable "drain_seconds" {
  description = "How long a host the group is taking away is held while it empties itself: the termination hook's timeout. At least the pool token's --shutdown-grace; the hook is left to expire, so this is also how long each scale-in takes."
  type        = number
  default     = 150
  nullable    = false
  validation {
    condition     = var.drain_seconds >= 30 && var.drain_seconds <= 7200
    error_message = "drain_seconds is between 30 and 7200, the hook's own bounds."
  }
}

variable "data_volume_gb" {
  description = "An EBS volume for the runner's data, for an instance type with no local NVMe. Zero uses the instance store, which is the right disk for volumes' cache and costs nothing more. A machine's boot takes an empty EBS volume where it has one, and the instance store otherwise."
  type        = number
  default     = 0
  nullable    = false
}

variable "root_volume_gb" {
  description = "The runner's root disk: the OS and the machine's files; its data is on the instance store or data_volume_gb."
  type        = number
  default     = 30
  nullable    = false
}

variable "session_manager" {
  description = "Let Session Manager reach the hosts. There is no SSH either way."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags on everything this module creates."
  type        = map(string)
  default     = {}
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
