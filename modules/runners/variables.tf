# Every variable with a default is nullable = false: null is "the default", so a module that wraps
# this one - the repository's root - passes what it was given without restating what it means.
#
# No name of its own: the control plane module's, which its group, role and SSM path are named
# for, and which its role and boundary name in turn. Two names were two things to keep equal.

variable "controlplane" {
  description = "The control plane module's outputs, as they are: its name, where the runners go, their document, and what a runner's machine runs at its first boot."
  type = object({
    name                = string
    iam_name            = string
    vpc_id              = string
    subnet_ids          = list(string)
    security_group_id   = string
    runner_document_arn = string
    runner_user_data    = string
    images              = map(object({ id = string, root_device = string }))
    boot_log_policy_arn = string
    standard_vcpus      = number
    boundary_arn        = string
  })
}

variable "instance_types" {
  description = <<-EOT
    The types the group may start, as EC2's allowed_instance_types takes them: names, or patterns
    with * (c8id.*). The group starts any type they match that has vcpus and the disk data_volume_gb
    leaves the data on - a local NVMe while it is 0, so a d variant - and AWS adds the sizes and
    types it brings out without this list changing.

    Keep them one CPU generation: a checkpoint records the processor and its flags as -cpu host
    showed them (MachineIdentity in spin's internal/runner/vmm), and resumes only onto a host that
    shows the same - a workspace suspended at night on one family and brought back on another
    cold-boots. Nested virtualization is offered on C8i, M8i, R8i (and their d variants), C7i, M7i,
    R7i and I7i. Not c8i* for c8i.*: that matches the flex types too.

    For spot, the more pools a request can draw on the likelier a machine, and one type is one
    pool per zone. How the types these match score in a region, before installing:
      aws ec2 get-spot-placement-scores --target-capacity 1 --region-names <region> \
        --single-availability-zone --instance-requirements-with-metadata \
        '{"ArchitectureTypes":["x86_64"],"InstanceRequirements":{"VCpuCount":{"Min":32,"Max":48},"MemoryMiB":{"Min":65536},"LocalStorage":"required","AllowedInstanceTypes":[<the types>]}}'
  EOT
  type        = list(string)
  default     = ["c8i.*", "c8id.*", "m8i.*", "m8id.*", "r8i.*", "r8id.*"]
  nullable    = false
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "instance_types names at least one."
  }
}

variable "vcpus" {
  description = "How many vCPUs a runner may have, at least and at most: each type instance_types matches within it is a pool the group may draw on. max is also what the quota is sized by (quota.tf)."
  type        = object({ min = number, max = number })
  default     = { min = 32, max = 48 }
  nullable    = false
  validation {
    condition     = var.vcpus.min >= 2 && var.vcpus.min <= var.vcpus.max
    error_message = "vcpus is min <= max, min at least 2."
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

variable "rollout" {
  description = "How a new release reaches the runners. idle: when the fleet next empties - no workspace running, starting or being saved - the next host boots it, and no workspace is moved for it; a host keeps the old release until then, which its control plane allows for 90 days. rolling: the hosts are replaced at once, one at a time, each old one's workspaces suspended to the bucket and resumed on the new one - for a fleet that never empties."
  type        = string
  default     = "idle"
  nullable    = false
  validation {
    condition     = contains(["idle", "rolling"], var.rollout)
    error_message = "rollout is idle or rolling."
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

variable "tags" {
  description = "Tags on everything this module creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

