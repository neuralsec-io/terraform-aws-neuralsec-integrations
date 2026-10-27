# cloud-scanner-role module and the shared policy chunker. Plan only with a mocked AWS
# provider: no credentials, no API calls.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
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
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker"
}

run "role_name_is_fixed" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = aws_iam_role.this.name == "neuralsec-cloud-scanner"
    error_message = "The member role name is part of the scanner contract and must not change."
  }
}

run "trust_policy_only_trusts_the_broker_with_the_external_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
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

  assert {
    condition     = alltrue([for s in jsondecode(output.trust_policy).Statement : alltrue([for a in s.Action : !strcontains(a, "*")])])
    error_message = "The trust policy must not contain action wildcards."
  }
}

run "policies_cover_exactly_the_exported_account_actions" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = sort(distinct(flatten([
      for doc in output.policy_documents : jsondecode(doc).Statement[0].Action
    ]))) == sort(distinct(jsondecode(file("${path.cwd}/modules/policy/actions.json")).account))
    error_message = "The union of the attached policies must equal the account action set of actions.json."
  }

  assert {
    condition     = output.policy_chunk_count >= 1 && output.policy_chunk_count <= 10
    error_message = "IAM allows at most 10 customer managed policies per role."
  }

  assert {
    condition     = output.policy_max_document_bytes <= 6144
    error_message = "No generated policy document may exceed the IAM limit of 6144 characters."
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
        for action in jsondecode(doc).Statement[0].Action : !startswith(action, "organizations:")
      ])
    ])
    error_message = "Organizations actions belong to the org-reader role, never the member role."
  }
}

run "rejects_a_malformed_external_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    external_id = "neuralsec-not-a-hex-id"
  }

  expect_failures = [var.external_id]
}

run "eks_clusters_get_a_view_only_access_entry" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    eks_clusters = ["ns-e2e-cluster"]
  }

  assert {
    condition     = aws_eks_access_entry.this["ns-e2e-cluster"].cluster_name == "ns-e2e-cluster"
    error_message = "The EKS access entry must cover the requested cluster."
  }

  assert {
    condition     = aws_eks_access_entry.this["ns-e2e-cluster"].type == "STANDARD"
    error_message = "Access entries must be STANDARD, never a bootstrap type."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["ns-e2e-cluster"].access_scope[0].type == "cluster"
    error_message = "The view policy must be scoped to the whole cluster and nothing wider."
  }
}

run "synthetic_action_list_is_split_across_several_policies" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = [for i in range(300) : "syntheticservice:ListSomethingWithAVeryLongName${i}"]
  }

  assert {
    condition     = length(output.documents) > 1
    error_message = "A 300 action list must not fit in a single policy document."
  }

  assert {
    condition     = output.chunk_count <= 10
    error_message = "A 300 action list must fit inside 10 managed policies."
  }

  assert {
    condition     = output.max_document_bytes <= 6144
    error_message = "Chunking must keep every policy document under the IAM limit of 6144 characters."
  }

  assert {
    condition = sort(distinct(flatten([
      for doc in output.documents : jsondecode(doc).Statement[0].Action
    ]))) == sort(distinct([for i in range(300) : "syntheticservice:ListSomethingWithAVeryLongName${i}"]))
    error_message = "Chunking must not drop, duplicate or reorder actions."
  }
}

run "named_read_exceptions_are_accepted" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["apigateway:GET", "iam:GenerateCredentialReport", "iam:ListRoles"]
  }

  assert {
    condition     = output.chunk_count == 1
    error_message = "The named read exceptions must pass validation."
  }
}

run "rejects_a_content_read_action" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "s3:getObject"]
  }

  expect_failures = [var.actions]
}

run "rejects_a_write_action" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "iam:CreateRole"]
  }

  expect_failures = [var.actions]
}
