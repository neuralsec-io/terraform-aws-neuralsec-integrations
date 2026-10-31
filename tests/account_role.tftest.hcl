# cloud-scanner-role module and the shared policy chunker. Plan only with a mocked AWS
# provider: no credentials, no API calls.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name   = "eu-west-1"
      region = "eu-west-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:iam::111111111111:user/example"
      user_id    = "AIDAEXAMPLEEXAMPLE01"
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
        for action in jsondecode(doc).Statement[0].Action : (!startswith(action, "organizations:") || action == "organizations:DescribeOrganization")
      ])
    ])
    error_message = "Organizations actions belong to the org-reader role, never the member role, except the dual read organizations:DescribeOrganization."
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

run "eks_access_entry_carries_the_rbac_group" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    eks_clusters = ["example"]
  }

  assert {
    condition     = aws_eks_access_entry.this["example"].kubernetes_groups == toset(["neuralsec:scanner-rbac-view"])
    error_message = "The EKS access entry must place the role in the neuralsec:scanner-rbac-view group."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["example"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    error_message = "The EKS view policy association must stay AmazonEKSViewPolicy, never the admin view policy."
  }
}

run "rbac_manifest_is_read_only_rbac_only" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    eks_clusters = ["example"]
  }

  assert {
    condition     = output.eks_rbac_group == "neuralsec:scanner-rbac-view" && strcontains(file(output.eks_rbac_manifest_path), "name: neuralsec:scanner-rbac-view")
    error_message = "The manifest must bind the same group the access entry sets."
  }

  assert {
    condition = alltrue([
      for word in ["secrets", "configmaps", "\"*\""] :
      !strcontains(join("\n", [for l in split("\n", file(output.eks_rbac_manifest_path)) : l if !startswith(trimspace(l), "#")]), word)
    ])
    error_message = "The manifest must not grant secrets, configmaps or wildcards."
  }

  assert {
    condition     = strcontains(file(output.eks_rbac_manifest_path), "verbs: [\"list\"]") && length(regexall("verbs:", file(output.eks_rbac_manifest_path))) == 1
    error_message = "The manifest must only grant list, in its single rule."
  }
}

# A description change forces IAM managed policy replacement, which fails under
# the fixed policy name in CloudFormation and drops the role's permissions for
# the apply in Terraform. The first policy keeps the description every earlier
# release created, whatever the chunk count; later policies never name the total.
run "first_policy_description_is_stable_across_chunk_counts" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = aws_iam_policy.read[0].description == "Neuralsec cloud scanner read actions, part 1 of 1."
    error_message = "The first read policy must keep its released description, or upgrades replace it."
  }

  assert {
    condition = alltrue([
      for i, p in aws_iam_policy.read : i == 0 || p.description == "Neuralsec cloud scanner read actions, part ${i + 1}."
    ])
    error_message = "Later read policies must not name the chunk total."
  }
}

# The IaC state exception. Without an input no state grant exists at all: the
# role keeps a read-only account policy and nothing that could read an object.
# It is also a zero diff for a role installed by an earlier release: no policy,
# no attachment, no guard and no tag appears, and the policy guard keeps the
# input shape it always had.
run "no_state_location_grants_nothing" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = (
      output.iac_state_policy_document == "" &&
      length(aws_iam_policy.iac_state) == 0 &&
      length(aws_iam_role_policy_attachment.iac_state) == 0
    )
    error_message = "A role without state_locations must not carry a state policy."
  }

  assert {
    condition     = length(output.state_location_tags) == 0 && try(length(aws_iam_role.this.tags), 0) == 0
    error_message = "A role without state_locations must not carry a state location tag."
  }

  assert {
    condition     = length(terraform_data.state_location_guard) == 0
    error_message = "A role without state_locations must not create the guard, or an upgrade plans a new resource."
  }

  assert {
    condition = (
      length(keys(terraform_data.policy_guard.input)) == 2 &&
      terraform_data.policy_guard.input["chunks"] == output.policy_chunk_count &&
      terraform_data.policy_guard.input["max_document_bytes"] == output.policy_max_document_bytes
    )
    error_message = "The policy guard input shape is part of the released state: a new key plans a change on every existing role."
  }

  assert {
    condition = alltrue([
      for doc in output.policy_documents : alltrue([
        for action in jsondecode(doc).Statement[0].Action : !contains(["s3:GetObject", "kms:Decrypt"], action)
      ])
    ])
    error_message = "The account read policy must never carry s3:GetObject or kms:Decrypt."
  }
}

# The registered locations are the grant and the discovery signal: one
# statement per read, scoped to the exact bucket, prefix and key, plus one
# numbered tag per location for Neuralsec to read.
run "state_locations_grant_exactly_the_registered_prefixes" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [
      {
        bucket      = "example-tf-state"
        prefix      = "prod/"
        kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      },
      {
        bucket = "example-pulumi-state"
        prefix = ".pulumi/stacks/"
        tool   = "pulumi"
        region = "us-east-1"
      },
    ]
  }

  assert {
    condition = sort(distinct(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Action
    ]))) == sort(jsondecode(file("${path.cwd}/modules/policy/actions.json")).iac_state)
    error_message = "The state policy must carry exactly the exported iac_state actions: the role tags are read with an action the account policy already grants."
  }

  assert {
    condition = sort(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if s.Sid == "IacStateGetRegisteredObjects"
      ])) == sort([
      "arn:aws:s3:::example-pulumi-state/.pulumi/stacks/*",
      "arn:aws:s3:::example-tf-state/prod/*",
    ])
    error_message = "s3:GetObject must be scoped to the registered bucket and prefix, never the bucket root."
  }

  assert {
    condition = sort(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if startswith(s.Sid, "IacStateListRegisteredPrefixes")
    ])) == sort(["arn:aws:s3:::example-pulumi-state", "arn:aws:s3:::example-tf-state"])
    error_message = "s3:ListBucket must be scoped to the registered buckets."
  }

  assert {
    condition     = length([for s in jsondecode(output.iac_state_policy_document).Statement : s if startswith(s.Sid, "IacStateListRegisteredPrefixes")]) == 2
    error_message = "Each bucket gets one s3:ListBucket statement, so a prefix of one bucket can never condition another bucket."
  }

  assert {
    condition = sort(distinct(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Condition.StringLike["s3:prefix"] if s.Sid == "IacStateListRegisteredPrefixes1"
    ]))) == sort(["prod/", "prod/*"])
    error_message = "The first bucket's listing must be conditioned on its own prefixes and their children."
  }

  assert {
    condition = sort(distinct(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Condition.StringLike["s3:prefix"] if s.Sid == "IacStateListRegisteredPrefixes2"
    ]))) == sort([".pulumi/stacks/", ".pulumi/stacks/*"])
    error_message = "The second bucket's listing must be conditioned on its own prefixes and their children."
  }

  assert {
    condition = flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : concat(s.Resource, flatten(s.Condition.StringEquals["kms:ViaService"])) if s.Sid == "IacStateDecryptRegisteredKeys"
      ]) == [
      "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab",
      "s3.eu-west-1.amazonaws.com",
    ]
    error_message = "kms:Decrypt must be scoped to the registered key and the S3 service of its region."
  }

  assert {
    condition     = length(aws_iam_policy.iac_state) == 1 && length(aws_iam_role_policy_attachment.iac_state) == 1
    error_message = "state_locations must attach exactly one extra managed policy."
  }

  assert {
    condition = output.state_location_tags == {
      "neuralsec:state-locations-1" = "dGVycmFmb3JtCmV1LXdlc3QtMQpleGFtcGxlLXRmLXN0YXRlCnByb2Qv"
      "neuralsec:state-locations-2" = "cHVsdW1pCnVzLWVhc3QtMQpleGFtcGxlLXB1bHVtaS1zdGF0ZQoucHVsdW1pL3N0YWNrcy8="
    }
    error_message = "The numbered tag is how Neuralsec learns the authoritative locations, so its encoding is a contract."
  }

  assert {
    condition = alltrue([
      for value in values(output.state_location_tags) :
      length(value) <= 256 && can(regex("^[\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*$", value))
    ])
    error_message = "Every tag value must fit the 256 character IAM limit and IAM's tag character set, or TagRole fails on apply."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.iac_state_policy_document).Statement :
      startswith(s.Sid, "IacStateGetRegisteredObjects") || alltrue([for r in s.Resource : !strcontains(r, "*")])
    ])
    error_message = "Only the object ARNs may carry a wildcard, and only the one that covers the registered prefix."
  }

  assert {
    condition     = length(aws_iam_role.this.tags) == 2 && aws_iam_role.this.tags["neuralsec:state-locations-1"] == output.state_location_tags["neuralsec:state-locations-1"]
    error_message = "The role must carry the state location tags the module exposes."
  }
}

run "state_locations_without_a_key_grant_no_kms" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "env:/" }]
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.iac_state_policy_document).Statement : !contains(s.Action, "kms:Decrypt")
    ])
    error_message = "Without a registered key the policy must not grant kms:Decrypt."
  }
}

run "rejects_a_malformed_state_bucket" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "Example_Bucket", prefix = "prod/" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_state_prefix_with_a_leading_slash" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "/prod/" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_duplicate_state_location" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [
      { bucket = "example-state", prefix = "prod/" },
      { bucket = "example-state", prefix = "prod/", tool = "pulumi" },
    ]
  }

  expect_failures = [var.state_locations]
}

run "rejects_an_unknown_state_tool" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/", tool = "cloudformation" }]
  }

  expect_failures = [var.state_locations]
}

# The prefix is a literal S3 key prefix: the module refuses the characters that
# would make the listing, the s3:prefix condition and the tag disagree.
run "rejects_a_state_prefix_with_a_wildcard" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/*/" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_state_prefix_with_a_question_mark" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/?/" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_state_prefix_with_a_template_marker" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/$${var.env}/" }]
  }

  expect_failures = [var.state_locations]
}

# kms:Decrypt takes a key ARN, never an alias ARN: an alias in the policy would
# grant nothing, because the S3 call arrives as the key ARN.
run "rejects_a_kms_alias_arn" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{
      bucket      = "example-state"
      prefix      = "prod/"
      kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:alias/example-state"
    }]
  }

  expect_failures = [var.state_locations]
}

# Two prefixes in one bucket share one statement, conditioned on both, so a
# bucket can never be listed under another bucket's prefix.
run "one_list_statement_per_bucket" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [
      { bucket = "example-state", prefix = "prod/" },
      { bucket = "example-state", prefix = "staging/" },
      { bucket = "example-other-state", prefix = "prod/" },
    ]
  }

  assert {
    condition     = length([for s in jsondecode(output.iac_state_policy_document).Statement : s if startswith(s.Sid, "IacStateListRegisteredPrefixes")]) == 2
    error_message = "Two buckets must produce two s3:ListBucket statements, whatever the number of prefixes."
  }

  assert {
    condition = sort(flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Condition.StringLike["s3:prefix"] if s.Resource[0] == "arn:aws:s3:::example-state" && startswith(s.Sid, "IacStateListRegisteredPrefixes")
    ])) == sort(["prod/", "prod/*", "staging/", "staging/*"])
    error_message = "A bucket's statement must carry only that bucket's prefixes."
  }
}
