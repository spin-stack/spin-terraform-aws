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

# The browser terminal's certificate: CloudFront takes one only from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Its terminal in term/ here: task term:fetch RELEASE=<spin_version>.
module "spin" {
  source       = "../.."
  providers    = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  spin_version = "v20260928.02"
  domain       = "example.com"
}

output "next_steps" {
  description = "DNS, the first sign-in, and how to reach a machine: tofu output -raw next_steps"
  value       = module.spin.next_steps
  sensitive   = true
}
