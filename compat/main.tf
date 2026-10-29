# Minimum-version check: every module at the oldest supported versions.
#
# This root is not a module. `scripts/check-min-versions.sh` writes
# `versions_override.tf` here pinning the AWS provider to one exact version,
# then runs `init -backend=false` and `validate`, so the module floors are
# proven instead of assumed.
#
# `sensor-lambda` is not listed: it needs Terraform 1.6 and AWS provider 5.0,
# above this root's floors, and is validated from `compat/sensor-lambda`.
# `sensor-eks` is not listed either: it needs the Helm provider 2.17, above
# this root's floors, and is validated from `compat/sensor-eks`.

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

module "sensor_ecs_sidecar" {
  source = "../modules/sensor-ecs-sidecar"

  container_definitions = "[{\"name\":\"app\",\"image\":\"public.ecr.aws/docker/library/eclipse-temurin:21-jre\"}]"
  app_containers        = ["app"]
  sidecar_image         = "public.ecr.aws/neuralsec/sensor-ecs@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  endpoint              = "https://sensor.example.com"
}

module "sensor_ec2" {
  source = "../modules/sensor-ec2"

  endpoint       = "https://sensor.example.com"
  sensor_version = "1.2.3"
  sha256 = {
    x86_64  = "0000000000000000000000000000000000000000000000000000000000000000"
    aarch64 = "1111111111111111111111111111111111111111111111111111111111111111"
  }
}
