# Both customer roles must render the same trust policy as the canonical fixture
# in tests/fixtures/trust_policy.json, and so must the CloudFormation templates
# (tools/cfngen asserts that half). Plan only with a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "eu-west-1"
      region = "eu-west-1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner"
      id  = "AROAEXAMPLEEXAMPLE01"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::111111111111:policy/neuralsec-cloud-scanner-read-01"
      id  = "ANPAEXAMPLEEXAMPLE01"
    }
  }
}

variables {
  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"
}

run "member_role_trust_matches_the_fixture" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = jsondecode(output.trust_policy) == jsondecode(file("${path.cwd}/tests/fixtures/trust_policy.json"))
    error_message = "The member role trust policy must equal tests/fixtures/trust_policy.json."
  }
}

run "org_reader_trust_matches_the_fixture" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org"
  }

  assert {
    condition     = jsondecode(output.trust_policy) == jsondecode(file("${path.cwd}/tests/fixtures/trust_policy.json"))
    error_message = "The org reader trust policy must equal tests/fixtures/trust_policy.json."
  }
}
