# An installation: the control plane, and a spot runner while anybody is using one. The group
# starts empty; the first workspace of the day waits a few minutes for its host, and the group is
# emptied an hour after the last workspace stops - at once between 20:00 and 07:00.
#
#   tofu init && tofu apply -var spin_version=v20260921.02 -var domain=example.com -var zone=Z0123
#
# From elsewhere, the source is this repository at a tag:
#
#   source = "github.com/spin-stack/spin-terraform-aws?ref=<tag>"
#
# This is also what `task lint` validates the modules through.

terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "spin_version" {
  type = string
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
  source          = "../.."
  spin_version    = var.spin_version
  domain          = var.domain
  route53_zone_id = var.zone

  runner_idle_minutes = 60
  quiet_hours         = "20:00-07:00"
  time_zone           = "America/Argentina/Buenos_Aires"
  max_runners         = 1
}

output "dashboard" {
  value = module.spin.dashboard
}

output "controlplane_group" {
  description = "The control plane's group of one: its machine is the one instance in it, reached with aws ssm start-session --target <instance>, then: sudo spin-controlplane bootstrap-password"
  value       = module.spin.controlplane_group
}
