# The OpenTofu the modules need, and the second AWS provider the caller gives: CloudFront takes the
# browser terminal's certificate only from us-east-1. The root makes nothing itself, and each
# module pins the providers it uses.
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
