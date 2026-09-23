# The account's vCPU quota for the runners' kind of machine, which a new account has at 32: less
# than one runner of 48 vCPUs, and one runner of 32 beside nothing else. A group asked for a
# machine the quota does not cover answers with MaxSpotInstanceCountExceeded, the workspace waits
# for a host that never comes, and nothing says why. So the quota is read at plan, the increase
# that covers max_hosts of the largest type is asked of AWS by this apply (request_quota), and
# the plan says so while it is pending.

data "aws_ec2_instance_type" "runner" {
  for_each      = toset(var.instance_types)
  instance_type = each.value
}

locals {
  # Standard instances' quotas are in vCPUs: "All Standard (A, C, D, H, I, M, R, T, Z) Spot
  # Instance Requests", and the running on-demand one.
  quota_code = var.spot ? "L-34B43A08" : "L-1216C47A"
  largest    = max([for t in data.aws_ec2_instance_type.runner : t.default_vcpus]...)
  # max_hosts of the largest, and, on-demand, the control plane's and the proxy's machines, each
  # of which is two while an update replaces it.
  vcpus_needed = var.max_hosts * local.largest + (var.spot ? 0 : var.controlplane.standard_vcpus)
}

data "aws_servicequotas_service_quota" "runners" {
  service_code = "ec2"
  quota_code   = local.quota_code
}

# A request for more, made once: AWS grants most of them in minutes and some after a support
# case. Removing this from the configuration lowers nothing.
resource "aws_servicequotas_service_quota" "runners" {
  count        = var.request_quota && data.aws_servicequotas_service_quota.runners.value < local.vcpus_needed ? 1 : 0
  service_code = "ec2"
  quota_code   = local.quota_code
  value        = local.vcpus_needed
}

check "room_for_runners" {
  assert {
    condition = data.aws_servicequotas_service_quota.runners.value >= local.vcpus_needed
    error_message = join("", [
      "This account's ${data.aws_servicequotas_service_quota.runners.quota_name} quota in this region is ",
      "${data.aws_servicequotas_service_quota.runners.value} vCPUs, and ${var.max_hosts} runner(s) of up to ",
      "${local.largest} vCPUs need ${local.vcpus_needed}. ",
      var.request_quota ? "The increase is requested by this apply; until AWS grants it, a workspace waits for a runner that cannot start. " : "Request it (Service Quotas, code ${local.quota_code}) or set request_quota. ",
      "aws service-quotas list-requested-service-quota-change-history --service-code ec2 says how the request is going.",
    ])
  }
}
