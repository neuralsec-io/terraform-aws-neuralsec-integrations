# Minimum-version check for the modules that support AWS provider 4.x.
#
# `cloud-scanner-role` needs `aws_eks_access_entry.type` (provider 5.34), so it
# is left out here and the remaining two modules are validated alone at the
# exact 4.0.0 floor. `scripts/check-min-versions.sh` writes the
# `versions_override.tf` that pins the provider.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "cloud_scanner_org" {
  source = "../../modules/cloud-scanner-org"

  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"
}

module "codeartifact_read_role" {
  source = "../../modules/codeartifact-read-role"

  external_ids         = ["neuralsec-0123456789abcdef0123456789abcdef"]
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"

  domains = [
    { region = "eu-west-1", domain_owner = "222222222222", domain = "maven" },
  ]
}
