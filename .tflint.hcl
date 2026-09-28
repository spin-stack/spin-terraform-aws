# What validate does not know: that an instance type exists, that every variable and output says
# what it is and has a type, that each module pins the providers and the OpenTofu it needs. The AWS
# ruleset is fetched by `tflint --init` and checked against its release's signature.
plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# terraform_* rules name "Terraform"; this repository is OpenTofu, which reads the same blocks.
config {
  call_module_type = "local"
}

# The ruleset's list of instance types lags AWS's - t8i is not in 0.49 - and the modules already
# look every type up (data "aws_ec2_instance_type"), which refuses one that does not exist at plan.
rule "aws_launch_template_invalid_instance_type" {
  enabled = false
}

# A module here is split by what it makes - network.tf, bucket.tf, proxy.tf - each file with the
# variable only it reads beside the resources that read it, and an example or bootstrap/ is one
# file read top to bottom. main.tf/variables.tf/outputs.tf for their own sake would put every
# decision a screen away from its reason.
rule "terraform_standard_module_structure" {
  enabled = false
}

# A module's resources are named for what they are to the installation - "controlplane", "proxy",
# "volumes" - and a singleton "this" only where there is nothing else to call it.
rule "terraform_naming_convention" {
  enabled = true
}
