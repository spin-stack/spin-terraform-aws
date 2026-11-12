# The tags the bill is read by. A tag on a resource is not in the bill until it is a cost allocation
# tag, which is the account's to decide, once - not each installation's - and AWS refuses to
# activate one it has not yet seen on a resource: apply this with cost_allocation_tags = true once
# an installation has run for a day. One bootstrap per account owns it; another region's leaves it
# false.
#
# spin:installation is what an installation's budget (modules/controlplane/budget.tf) and the
# control plane's reading of the bill filter by; spin:role splits it into the control plane, the
# proxy, the database, the runners and the rest, which is how spin says what the installation costs
# with nobody working. spin:host-class is the class a runner's group is made for, which the control
# plane tags each group with and its machines and disks carry from launch: it splits the runners'
# cost by class.

variable "cost_allocation_tags" {
  description = "Activate spin's tags as cost allocation tags in this account: true once an installation has run a day here, in one bootstrap per account."
  type        = bool
  default     = false
}

resource "aws_ce_cost_allocation_tag" "spin" {
  for_each = var.cost_allocation_tags ? toset(["spin:installation", "spin:role", "spin:host-class"]) : toset([])
  tag_key  = each.value
  status   = "Active"
}
