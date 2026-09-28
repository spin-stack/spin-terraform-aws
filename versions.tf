# The OpenTofu the modules need. No provider: the root makes nothing itself, and each module pins
# the providers it uses.
terraform {
  required_version = ">= 1.11"
}
