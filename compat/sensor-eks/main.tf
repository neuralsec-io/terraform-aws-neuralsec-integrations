# Minimum-version check for `sensor-eks`.
#
# The module needs the Helm provider 2.17 or newer, which the repository
# default root does not declare, so it is validated alone here.
# `scripts/check-min-versions.sh` writes the `versions_override.tf` that pins
# the provider.

terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

module "sensor_eks" {
  source = "../../modules/sensor-eks"

  endpoint     = "https://sensor.example.com"
  cluster_name = "example-cluster"
  image_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
