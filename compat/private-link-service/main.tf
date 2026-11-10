# Minimum-version check for `private-link-service`.
#
# The module needs AWS provider 5.79 (the first release with `supported_regions`
# on `aws_vpc_endpoint_service`) and the time provider, above the repository
# default, so it is validated alone here. `scripts/check-min-versions.sh`
# writes the `versions_override.tf` that pins both providers.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

module "private_link_service" {
  source = "../../modules/private-link-service"

  name                    = "registry"
  neuralsec_org_id        = "00000000-0000-4000-8000-000000000000"
  neuralsec_org_slug      = "example"
  neuralsec_principal_arn = "arn:aws:iam::111111111111:role/neuralsec-app"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  target_ips = ["10.0.1.10"]
}
