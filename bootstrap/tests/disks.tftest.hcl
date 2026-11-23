# What bootstrap promises of the account's EBS, held against its plan with credentials nothing
# checks, as the modules' tests are.

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

variables {
  region = "us-east-2"
}

run "every_disk_in_the_region_is_encrypted" {
  command = plan

  assert {
    condition     = length(aws_ebs_encryption_by_default.this) == 1 && aws_ebs_encryption_by_default.this[0].enabled
    error_message = "EBS encryption by default is not on in the installations' region"
  }
}

run "images_published_elsewhere_leave_it_on" {
  command = plan

  variables {
    image_publishers = { "spin-stack/ami" = "repo:spin-stack/ami" }
    publish_regions  = ["us-east-1"]
  }

  assert {
    condition     = length(aws_ebs_encryption_by_default.this) == 1
    error_message = "a publish to another region turned off encryption by default in this one"
  }
}

run "not_where_public_images_are_written" {
  command = plan

  variables {
    image_publishers = { "spin-stack/ami" = "repo:spin-stack/ami" }
  }

  assert {
    condition     = length(aws_ebs_encryption_by_default.this) == 0
    error_message = "encryption by default is on in the region images are published in: their snapshots could not be public"
  }
}
