# Neuralsec sensor Terraform module.
#
# The module calls no provider: it is a pure computation over the inputs, so
# `terraform plan` works offline. The AWS provider is declared only so consumers
# inherit a working constraint in their lock file.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}
