# The tags the bill is read by. A tag on a resource is not in the bill until it is a cost allocation
# tag, which is the account's to decide, once - not each installation's - and AWS refuses to
# activate one it has not yet seen on a resource: apply this with cost_allocation_tags = true once
# an installation has run for a day. One bootstrap per account owns it; another region's leaves it
# false.
#
# spin:installation is what an installation's budget (modules/controlplane/budget.tf) and the
# control plane's reading of the bill filter by; spin:role splits it into the control plane, the
# proxy and the runners.

variable "cost_allocation_tags" {
  description = "Activate spin's tags as cost allocation tags in this account: true once an installation has run a day here, in one bootstrap per account."
  type        = bool
  default     = false
}

resource "aws_ce_cost_allocation_tag" "spin" {
  for_each = var.cost_allocation_tags ? toset(["spin:installation", "spin:role"]) : toset([])
  tag_key  = each.value
  status   = "Active"
}
