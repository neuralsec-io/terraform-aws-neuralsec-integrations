# Minimum-version check: every module at the oldest supported versions.
#
# This root is not a module. `scripts/check-min-versions.sh` writes
# `versions_override.tf` here pinning the AWS provider to one exact version,
# then runs `init -backend=false` and `validate`, so the module floors are
# proven instead of assumed.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "cloud_scanner_role" {
  source = "../modules/cloud-scanner-role"

  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"
  eks_clusters         = ["example"]
}

module "cloud_scanner_org" {
  source = "../modules/cloud-scanner-org"

  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"
}

module "codeartifact_read_role" {
  source = "../modules/codeartifact-read-role"

  external_ids         = ["neuralsec-0123456789abcdef0123456789abcdef"]
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"

  domains = [
    { region = "eu-west-1", domain_owner = "222222222222", domain = "maven" },
  ]
}
