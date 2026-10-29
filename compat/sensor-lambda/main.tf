# Minimum-version check for `sensor-lambda`.
#
# The module needs Terraform 1.6 and AWS provider 5.0, above the repository
# default, so it is validated alone here. `scripts/check-min-versions.sh`
# writes the `versions_override.tf` that pins the provider.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "sensor_lambda" {
  source = "../../modules/sensor-lambda"

  environment  = { "LOG_LEVEL" = "info" }
  layers       = []
  architecture = "x86_64"
  runtime      = "python3.12"
  package_type = "Zip"
  region       = "eu-west-1"
  endpoint     = "https://sensor.example.com"
}
