# An installation: the control plane, and a spot runner while anybody is using one. The group
# starts empty; the first workspace of the day waits a few minutes for its host, and the group is
# emptied an hour after the last workspace stops - at once between 20:00 and 07:00.
#
#   (once per account: cd ../../bootstrap && tofu init && tofu apply)
#   $(tofu -chdir=../../bootstrap output -raw init)
#   tofu apply -var spin_version=v20260921.02 -var spin_boot_sha256=<sha256> \
#     -var domain=example.com -var zone=Z0123
#
# From elsewhere, the source is this repository at a tag:
#
#   source = "github.com/spin-stack/spin-terraform-aws?ref=<tag>"
#
# This is also what `task lint` validates the modules through.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The state is in the bucket bootstrap/ made, one object per installation, and encrypted with
  # its key before it leaves this machine: it holds the installation's CA key. The bucket and its
  # region are given at init (bootstrap's `init` output).
  backend "s3" {
    key          = "${var.name}.tfstate"
    use_lockfile = true
  }
  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id = "alias/spin-tofu-state"
      region     = var.region
      key_spec   = "AES_256"
    }
    method "aes_gcm" "state" {
      keys = key_provider.aws_kms.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

variable "name" {
  description = "The installation's name: its resources, its SSM path, and its state's object in the bucket."
  type        = string
  default     = "spin"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "spin_version" {
  type = string
}

variable "spin_boot_sha256" {
  description = "The SHA-256 of that release's spin-boot-linux-amd64, from its checksums.txt."
  type        = string
}

variable "domain" {
  type = string
}

variable "zone" {
  description = "The Route 53 zone for the domain; empty writes no records."
  type        = string
  default     = ""
}

provider "aws" {
  region = var.region
}

module "spin" {
  source           = "../.."
  name             = var.name
  spin_version     = var.spin_version
  spin_boot_sha256 = var.spin_boot_sha256
  domain           = var.domain
  route53_zone_id  = var.zone

  runner_idle_minutes = 60
  quiet_hours         = "20:00-07:00"
  time_zone           = "America/Argentina/Buenos_Aires"
  max_runners         = 1
}

output "dashboard" {
  value = module.spin.dashboard
}

output "next_steps" {
  description = "DNS, the first sign-in, and how to reach a machine: tofu output -raw next_steps"
  value       = module.spin.next_steps
}
