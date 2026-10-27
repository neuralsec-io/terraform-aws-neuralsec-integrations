# cloud-scanner-org module. Plan only with a mocked AWS provider.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-org-reader"
      id  = "AROAEXAMPLEEXAMPLE02"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::111111111111:policy/neuralsec-cloud-scanner-org-reader-read-01"
      id  = "ANPAEXAMPLEEXAMPLE02"
    }
  }
}

variables {
  external_id          = "neuralsec-fedcba9876543210fedcba9876543210"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker"
}

run "role_name_is_fixed" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org"
  }

  assert {
    condition     = aws_iam_role.this.name == "neuralsec-cloud-scanner-org-reader"
    error_message = "The org reader role name is part of the scanner contract and must not change."
  }
}

run "trust_policy_only_trusts_the_broker_with_the_external_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org"
  }

  assert {
    condition     = length(jsondecode(output.trust_policy).Statement) == 1
    error_message = "The trust policy must hold exactly one statement."
  }

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Principal.AWS == var.neuralsec_broker_arn
    error_message = "The trust policy must trust the Neuralsec broker role and nothing else."
  }

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == var.external_id
    error_message = "The trust policy must require sts:ExternalId equal to the module input."
  }
}

run "policies_cover_exactly_the_exported_org_reader_actions" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org"
  }

  assert {
    condition = sort(distinct(flatten([
      for doc in output.policy_documents : jsondecode(doc).Statement[0].Action
    ]))) == sort(distinct(jsondecode(file("${path.cwd}/modules/policy/actions.json")).org_reader))
    error_message = "The union of the attached policies must equal the org_reader action set of actions.json."
  }

  assert {
    condition = alltrue([
      for doc in output.policy_documents : alltrue([
        for action in jsondecode(doc).Statement[0].Action : !strcontains(action, "*")
      ])
    ])
    error_message = "No policy statement may contain an action wildcard."
  }

  assert {
    condition = alltrue([
      for doc in output.policy_documents : alltrue([
        for action in jsondecode(doc).Statement[0].Action : startswith(action, "organizations:")
      ])
    ])
    error_message = "The org reader holds organizations read actions only."
  }

  assert {
    condition     = output.policy_max_document_bytes <= 6144
    error_message = "No generated policy document may exceed the IAM limit of 6144 characters."
  }
}

run "rejects_a_malformed_external_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org"
  }

  variables {
    external_id = "neuralsec-"
  }

  expect_failures = [var.external_id]
}
