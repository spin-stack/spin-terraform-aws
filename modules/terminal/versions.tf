terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # CloudFront takes a certificate only from us-east-1, whatever region the installation is in.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
