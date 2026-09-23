# What the control plane starts on, kept where its machines are not: one document in the
# parameter store, read at every start by the role of whichever machine is leading (spin's
# internal/bootstrap, behind internal/configsource). A machine of this installation is replaced
# by design - an update stands a new one beside the old - so nothing an installation decides is
# assembled onto its disk by a boot script: the values are here, and the boot passes a location.
#
# It is short, and meant to stay short. Everything an administrator can change once the catalog
# is open is in the catalog, declared in installation.yaml (machine_files.tf) and applied there;
# what is left here is what a process needs *before* it can read the catalog, and the one thing
# fixed at the first start:
#
#   database   where the catalog is and how this machine signs in to it - the fact everything
#              else is behind, so it cannot be in the thing it opens.
#   tls        the names the control plane's certificate must cover. Not policy: the certificate
#              is made at the first start, before any configuration of the catalog is applied,
#              and re-issuing one in use is a restart of every runner's connection.
#   production what a development installation may do and this one may not.
#
# The encryption key is not in it and never passes through Terraform: what is here is where the
# key is, and the first machine to boot makes it and stores it (user_data.sh.tftpl). So this
# parameter holds no secret - the secret is a parameter of its own, read by the same role - and
# the state file of an apply holds neither.
#
# A change here reaches a control plane when one next starts, and not before: it is read at
# start, like everything a process needs before its catalog. Nothing in it can be changed under a
# running installation without also replacing the machine - which is why so little is in it, and
# why what an administrator changes is the catalog's.
#
# No path on a machine is here either. Where the CA it writes goes, and where the database's
# bundle was put, are the layout spin-install owns; an installation repeating them would be the
# same fact in two places, and the one that lost would lose silently.

locals {
  config_parameter = "/${var.name}/controlplane-config"

  # Telemetry is not here: where this installation pushes is its own policy, declared in
  # installation.yaml (instance.tf) and read once the catalog is open. An installation is not
  # asked for a collector before it has one, and the one this module runs is on the machine this
  # document is for.
  controlplane_document = {
    database = {
      url = local.database_url
      # An RDS token signed per connection by this machine's role: the catalog has no password
      # to keep anywhere, so there is nothing here to rotate or to leak.
      auth = "aws-iam"
    }
    encryption_key_at = "ssm://${local.key_parameter}"
    tls               = { extra_sans = [local.cp_host] }
    production        = true

    # What the machine's first boot does, and what the control plane never reads: the release it
    # installs, and the store the catalog is told about once. It is in this document rather than
    # in the user data because the user data is three lines that fetch spin-boot — everything a
    # machine is, it reads from here (spin's internal/bootstrap, Install).
    install = {
      release = var.spin_version
      store = {
        bucket   = aws_s3_bucket.volumes.bucket
        region   = local.region
        role_arn = aws_iam_role.runner_scope.arn
      }
    }
  }
}

resource "aws_ssm_parameter" "controlplane_config" {
  name        = local.config_parameter
  description = "What ${var.name}'s control plane starts on: its catalog, where its key is, and the names its certificate covers"
  type        = "String"
  value       = yamlencode(local.controlplane_document)
  tags        = local.tags
}
