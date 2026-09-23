terraform {
  # Write-only attributes and ephemeral resources: the encryption key and the first
  # administrator's password are made during an apply and written to SSM without ever being in
  # the state (secrets.tf).
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
  }
}
