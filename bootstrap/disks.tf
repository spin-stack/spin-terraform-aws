# Every EBS volume made in this account and region is encrypted, whoever makes it: an
# installation's machines name its own key (modules/controlplane/disks.tf), and anything else gets
# the account's aws/ebs. Here rather than in an installation, since it is the account's setting in
# the region: a second installation would share it, and the destroy of either would turn it off.
# The default key stays aws/ebs for the same reason: two installations' keys cannot both be it.
#
# Not in a region this account publishes Spin OS in: a snapshot written there would be encrypted,
# and AWS shares no encrypted snapshot publicly.
locals {
  publishes_here = length(var.image_publishers) > 0 && contains(coalescelist(var.publish_regions, [var.region]), var.region)
}

resource "aws_ebs_encryption_by_default" "this" {
  count   = local.publishes_here ? 0 : 1
  enabled = true
}
