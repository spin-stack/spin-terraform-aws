# An installation: the control plane, and one spot runner during working hours.
#
#   tofu init && tofu apply -var spin_version=v20260921.02 -var domain=example.com -var zone=Z0123
#
# This is also what `task lint:terraform` validates the two modules through.

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

module "controlplane" {
  source          = "../controlplane"
  spin_version    = var.spin_version
  domain          = var.domain
  route53_zone_id = var.zone
}

module "runners" {
  source       = "../runners"
  spin_version = var.spin_version
  controlplane = module.controlplane
  size         = 1
  schedule = {
    up        = "0 8 * * MON-FRI"
    down      = "0 18 * * MON-FRI"
    time_zone = "America/Argentina/Buenos_Aires"
  }
}

output "dashboard" {
  value = "https://app.${var.domain}"
}

output "controlplane_instance" {
  description = "aws ssm start-session --target <this>, then: sudo docker exec spin-controlplane controlplane bootstrap-password"
  value       = module.controlplane.instance_id
}
