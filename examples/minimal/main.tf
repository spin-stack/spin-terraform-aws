# The least an installation is: a release and a domain, every other decision the modules' default.
# examples/complete is the same with a state bucket, an encrypted state and the choices an
# installation usually makes; this one is what `task lint` holds the defaults to - that nothing
# else is required.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "spin" {
  source       = "../.."
  spin_version = "v20260928.02"
  domain       = "example.com"
}

output "next_steps" {
  description = "DNS, the first sign-in, and how to reach a machine: tofu output -raw next_steps"
  value       = module.spin.next_steps
  sensitive   = true
}
