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

variable "runners" {
  description = "The control plane module's runners output: what it decides of the runners - the launch template's name, which it makes each host class's group from, its role, what the template's machines need of an instance type, and what the quota is sized by."
  type = object({
    launch_template       = string
    controlplane_role     = string
    vcpus_max             = number
    max_hosts             = number
    spot                  = bool
    data_volume_gb        = number
    nested_virtualization = bool
  })
}

variable "request_quota" {
  description = "Ask AWS for the vCPU quota max_hosts runners need, when the account's is lower (quota.tf). A request costs nothing and lowers nothing when it is removed."
  type        = bool
  default     = true
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

