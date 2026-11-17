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

run "role_carries_the_release_version_tag" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = (
      aws_iam_role.this.tags["neuralsec:integration-version"] == jsondecode(file("${path.cwd}/modules/policy/version.json")).integration_version &&
      aws_iam_role.this.tags["neuralsec:integration-version"] == regex("(?m)^## v([0-9]+[.][0-9]+[.][0-9]+)", file("${path.cwd}/../CHANGELOG.md"))[0]
    )
    error_message = "The role must carry neuralsec:integration-version equal to the newest CHANGELOG release."
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
    condition     = output.policy_chunk_count >= 1 && output.policy_chunk_count + 1 <= 10
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

# apigateway:GET can return API key values and the exported or SDK bundle of a
# stage, so the role carries an explicit Deny on those paths. The same statement
# is generated into the CloudFormation template by tools/cfngen.
run "api_gateway_content_paths_are_denied" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = jsondecode(output.deny_policy_document).Statement == [{
      Sid    = "DenyApiGatewayContentPaths"
      Effect = "Deny"
      Action = ["apigateway:GET"]
      Resource = [
        "arn:aws:apigateway:*::/apikeys",
        "arn:aws:apigateway:*::/apikeys/*",
        "arn:aws:apigateway:*::/apis/*/exports/*",
        "arn:aws:apigateway:*::/restapis/*/stages/*/exports/*",
        "arn:aws:apigateway:*::/restapis/*/stages/*/sdks/*",
        "arn:aws:apigateway:*::/usageplans/*/keys",
        "arn:aws:apigateway:*::/usageplans/*/keys/*",
      ]
    }]
    error_message = "The deny policy must deny apigateway:GET on the API key, export and SDK paths and nothing else."
  }

  assert {
    condition     = aws_iam_policy.deny.name == "neuralsec-cloud-scanner-deny" && aws_iam_role_policy_attachment.deny.role == "neuralsec-cloud-scanner"
    error_message = "The deny policy must be attached to the role."
  }

  assert {
    condition     = alltrue([for doc in output.policy_documents : alltrue([for s in jsondecode(doc).Statement : s.Effect == "Allow"])])
    error_message = "The read policies must hold Allow statements only."
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
    condition     = aws_eks_access_policy_association.this["ns-e2e-cluster"].access_scope[0].type == "cluster" && aws_eks_access_policy_association.this["ns-e2e-cluster"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    error_message = "For this release the view policy stays associated by default, scoped to the cluster, so clusters without the ClusterRole keep their inventory."
  }

  assert {
    condition     = output.eks_upgrade_notice != ""
    error_message = "While the broader policy is associated the module must say how to move to the list-only ClusterRole."
  }
}

run "list_only_access_drops_the_view_policy" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    eks_clusters                = ["ns-e2e-cluster"]
    eks_view_policy_association = false
  }

  assert {
    condition     = length(aws_eks_access_policy_association.this) == 0 && length(aws_eks_access_entry.this) == 1
    error_message = "With eks_view_policy_association = false only the access entry remains: the ClusterRole is the whole Kubernetes grant."
  }

  assert {
    condition     = output.eks_upgrade_notice == ""
    error_message = "No upgrade notice once the list-only access is in place."
  }
}

run "synthetic_action_list_is_split_across_several_policies" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = [for i in range(300) : "synthetic${i % 30}:ListSomethingWithAVeryLongName${i}"]
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
    ]))) == sort(distinct([for i in range(300) : "synthetic${i % 30}:ListSomethingWithAVeryLongName${i}"]))
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
    condition     = length(flatten([for doc in output.documents : jsondecode(doc).Statement[0].Action])) == 3
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

run "rejects_the_lambda_layer_content_read" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "lambda:GetLayerVersion"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_credential_vending_action" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "sts:GetSessionToken"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_credential_vending_action_in_any_case" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "STS:getfederationtoken"]
  }

  expect_failures = [var.actions]
}

run "rejects_a_name_matching_the_credentials_pattern" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "newservice:GetThingCredentials"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_name_matching_the_password_pattern_in_any_case" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "newservice:getadminpassword"]
  }

  expect_failures = [var.actions]
}

run "rejects_a_name_matching_the_get_object_suffix" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "newservice:GetObject"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_name_matching_the_query_results_suffix" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "newservice:GetBigQueryResults"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_name_matching_the_get_records_suffix" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "newservice:GetRecords"]
  }

  expect_failures = [output.documents]
}

run "rejects_the_ecr_authorization_token" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "ecr:GetAuthorizationToken"]
  }

  expect_failures = [output.documents]
}

run "rejects_a_dynamodb_item_read" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:ListRoles", "dynamodb:BatchGetItem"]
  }

  expect_failures = [output.documents]
}

run "pattern_exceptions_stay_allowed" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["iam:GetAccountPasswordPolicy", "iam:ListServiceSpecificCredentials"]
  }

  assert {
    condition     = output.chunk_count == 1
    error_message = "The two named metadata reads that match a pattern must stay allowed."
  }
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

}

# Customers that restrict the EKS public endpoint need the addresses the
# scanner connects from. The lists are constants of the module, so this pins
# their exact content: one IPv6 /56 and three IPv4 /32s, in the published
# order, with the combined list IPv6 first.
run "scanner_egress_ipv4_cidrs_are_the_published_addresses" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = output.scanner_egress_ipv4_cidrs == [
      "3.248.10.74/32",
      "34.241.8.107/32",
      "52.16.218.0/32",
    ]
    error_message = "The IPv4 egress list must be the three published IPv4 addresses, each a /32."
  }

  assert {
    condition     = length(distinct(output.scanner_egress_ipv4_cidrs)) == length(output.scanner_egress_ipv4_cidrs)
    error_message = "The IPv4 egress list must not repeat an address."
  }

  assert {
    condition = alltrue([
      for cidr in output.scanner_egress_ipv4_cidrs :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", cidr))
    ])
    error_message = "Every IPv4 egress entry must be an IPv4 /32, because the scanner's IPv4 path uses fixed addresses."
  }
}

run "scanner_egress_ipv6_cidrs_are_the_published_prefix" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = output.scanner_egress_ipv6_cidrs == ["2a05:d018:e21:f00::/56"]
    error_message = "The IPv6 egress list must be the one published /56."
  }

  assert {
    condition = alltrue([
      for cidr in output.scanner_egress_ipv6_cidrs :
      can(regex("^[0-9a-f:]+/[0-9]{1,3}$", cidr)) && strcontains(cidr, ":") && !strcontains(cidr, ".")
    ])
    error_message = "Every IPv6 egress entry must be a bare IPv6 CIDR, because the scanner's IPv6 path is IPv6 only."
  }
}

run "scanner_egress_cidrs_combine_both_families_ipv6_first" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = output.scanner_egress_cidrs == concat(output.scanner_egress_ipv6_cidrs, output.scanner_egress_ipv4_cidrs)
    error_message = "scanner_egress_cidrs is the convenience list of both families, IPv6 first."
  }

  assert {
    condition     = length(distinct(output.scanner_egress_cidrs)) == length(output.scanner_egress_cidrs)
    error_message = "The combined egress list must not repeat a prefix."
  }
}

run "rbac_manifest_is_list_only_on_the_scanned_resources" {
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
      for word in ["secrets", "configmaps", "pods/log", "\"*\"", "get", "watch"] :
      !strcontains(join("\n", [for l in split("\n", file(output.eks_rbac_manifest_path)) : l if !startswith(trimspace(l), "#")]), word)
    ])
    error_message = "The manifest must not grant secrets, configmaps, pod logs, wildcards or any verb but list."
  }

  assert {
    condition = (
      length(regexall("verbs:", file(output.eks_rbac_manifest_path))) == 5 &&
      length(regexall("verbs: \\[\"list\"\\]", file(output.eks_rbac_manifest_path))) == 5
    )
    error_message = "Every rule of the manifest must grant list only."
  }

  # The exact resource set the scanner lists, by API group.
  assert {
    condition = alltrue([
      for word in [
        "resources: [\"deployments\", \"statefulsets\", \"daemonsets\"]",
        "resources: [\"cronjobs\"]",
        "resources: [\"pods\", \"services\", \"serviceaccounts\"]",
        "resources: [\"ingresses\"]",
        "resources: [\"roles\", \"clusterroles\", \"rolebindings\", \"clusterrolebindings\"]",
      ] : strcontains(file(output.eks_rbac_manifest_path), word)
    ])
    error_message = "The manifest must list exactly the workload, networking and RBAC resources the scanner reads."
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
    condition     = aws_iam_policy.read["1"].description == "Neuralsec cloud scanner read actions, part 1 of 1."
    error_message = "The first read policy must keep its released description, or upgrades replace it."
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_policy.read : k == "1" || p.description == "Neuralsec cloud scanner read actions, part ${k}."
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
    condition     = length(output.state_location_tags) == 0 && length(aws_iam_role.this.tags) == 1 && contains(keys(aws_iam_role.this.tags), "neuralsec:integration-version")
    error_message = "A role without state_locations must carry only the release version tag and no state location tag."
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
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if startswith(s.Sid, "IacStateGetRegisteredObjects")
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
      for s in jsondecode(output.iac_state_policy_document).Statement : concat(s.Resource, flatten(s.Condition.StringEquals["kms:ViaService"])) if startswith(s.Sid, "IacStateDecryptRegisteredKeys")
      ]) == [
      "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab",
      "s3.eu-west-1.amazonaws.com",
    ]
    error_message = "kms:Decrypt must be scoped to the registered key and the S3 service of its region."
  }

  assert {
    condition = flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Condition.StringLike["kms:EncryptionContext:aws:s3:arn"] if startswith(s.Sid, "IacStateDecryptRegisteredKeys")
      ]) == [
      "arn:aws:s3:::example-tf-state",
      "arn:aws:s3:::example-tf-state/prod/*",
    ]
    error_message = "kms:Decrypt must be tied to the registered bucket and prefix by encryption context."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.iac_state_policy_document).Statement :
      !contains(s.Action, "kms:Decrypt") ? s.Condition.StringEquals["aws:ResourceAccount"] == ["111111111111"] : true
    ])
    error_message = "Every S3 grant must be pinned to the bucket owner account, by default the account of the role."
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
    condition     = length(aws_iam_role.this.tags) == 3 && aws_iam_role.this.tags["neuralsec:state-locations-1"] == output.state_location_tags["neuralsec:state-locations-1"]
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

run "bucket_owner_pins_the_account_per_bucket" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [
      { bucket = "example-central-state", prefix = "prod/", bucket_owner = "222222222222" },
      { bucket = "example-local-state", prefix = "prod/" },
    ]
  }

  assert {
    condition = join(",", sort([
      for s in jsondecode(output.iac_state_policy_document).Statement : "${s.Resource[0]}=${s.Condition.StringEquals["aws:ResourceAccount"][0]}"
      if startswith(s.Sid, "IacStateGetRegisteredObjects")
    ])) == "arn:aws:s3:::example-central-state/prod/*=222222222222,arn:aws:s3:::example-local-state/prod/*=111111111111"
    error_message = "Each object grant must be pinned to the owner of its bucket."
  }
}

run "exact_state_key_is_granted_without_a_wildcard" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/network.tfstate" }]
  }

  assert {
    condition = flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if startswith(s.Sid, "IacStateGetRegisteredObjects")
    ]) == ["arn:aws:s3:::example-state/prod/network.tfstate"]
    error_message = "An exact .tfstate key must be granted as that one object."
  }
}

run "whole_bucket_is_an_explicit_opt_in" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", whole_bucket = true }]
  }

  assert {
    condition = flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if startswith(s.Sid, "IacStateGetRegisteredObjects")
    ]) == ["arn:aws:s3:::example-state/*"]
    error_message = "whole_bucket must grant every object of the bucket."
  }
}

run "rejects_an_empty_state_prefix_without_whole_bucket" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_state_prefix_that_is_neither_a_folder_nor_a_tfstate_key" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod" }]
  }

  expect_failures = [var.state_locations]
}

run "pulumi_exact_json_key_is_granted_and_terraform_json_is_not" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = ".pulumi/stacks/example/prod.json", tool = "pulumi" }]
  }

  assert {
    condition = flatten([
      for s in jsondecode(output.iac_state_policy_document).Statement : s.Resource if startswith(s.Sid, "IacStateGetRegisteredObjects")
    ]) == ["arn:aws:s3:::example-state/.pulumi/stacks/example/prod.json"]
    error_message = "A pulumi exact .json key must be granted as that one object."
  }
}

run "rejects_a_json_key_for_terraform" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/network.json" }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_whole_bucket_with_a_prefix" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/", whole_bucket = true }]
  }

  expect_failures = [var.state_locations]
}

run "rejects_a_malformed_bucket_owner" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  variables {
    state_locations = [{ bucket = "example-state", prefix = "prod/", bucket_owner = "abc" }]
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

# Actions are grouped by service, so one added action changes one policy and
# leaves the others byte for byte as they were.
run "adding_one_action_changes_one_policy" {
  command = plan

  module {
    source = "./tests/fixtures/chunk-pair"
  }

  assert {
    condition     = length(output.plus_one) == length(output.base)
    error_message = "One added action must not change the number of policies."
  }

  assert {
    condition     = length([for i, doc in output.plus_one : doc if doc != output.base[i]]) == 1
    error_message = "One added action must change exactly one policy document."
  }

  assert {
    condition     = output.reversed == output.base
    error_message = "The policies must not depend on the order of the input list."
  }
}

run "a_service_over_the_budget_fails_the_plan" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = [for i in range(300) : "oneservice:ListSomethingWithAVeryLongName${i}"]
  }

  expect_failures = [output.documents]
}

# The service buckets are shared with tools/cfngen, which pins the same hash
# values, so the CloudFormation templates and this module cut identical
# policies. The published list needs six read policies in both.
run "service_hash_and_published_chunks_match_cfngen" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition = alltrue([
      length(output.policy_documents) > 0,
      parseint(substr(md5("iam"), 0, 8), 16) == 247224330,
      parseint(substr(md5("ec2"), 0, 8), 16) == 3632470495,
      parseint(substr(md5("s3"), 0, 8), 16) == 3229781507,
      parseint(substr(md5("lambda"), 0, 8), 16) == 2489270212,
    ])
    error_message = "The service hash must equal the value pinned in tools/cfngen."
  }

  assert {
    condition     = output.policy_chunk_count == 6
    error_message = "The published action list must produce the same six read policies as the CloudFormation template."
  }

  assert {
    condition     = length(aws_iam_policy.read) + 1 + 1 <= 10
    error_message = "Attached read policies plus the deny and IaC state policies must fit the 10 policy cap."
  }
}

# A service whose home bucket would pass the byte budget moves to the next
# bucket, and the plan stays inside 6 policies. The same list and the same
# counts per policy are pinned in tools/cfngen.
run "an_overflowing_bucket_spills_to_the_next_one" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions          = flatten([for s in range(10) : [for i in range(10) : "ovf${s}:DescribeSomethingLongEnough${i}"]])
    max_policy_bytes = 1000
  }

  assert {
    condition     = output.chunk_numbers == [1, 2, 3, 4, 5, 6] && [for doc in output.documents : length(jsondecode(doc).Statement[0].Action)] == [20, 20, 10, 10, 20, 20]
    error_message = "The overflowing bucket must move one service to the next bucket, as tools/cfngen does."
  }

  assert {
    condition     = length(flatten([for doc in output.documents : jsondecode(doc).Statement[0].Action])) == 100
    error_message = "Spilling must not drop or duplicate actions."
  }
}

# The per-policy action lists equal the ones tools/cfngen generates for the
# CloudFormation templates from the same actions.json: policy-chunks.json is
# written by cfngen and kept fresh by `cfngen --check`.
run "policies_match_the_cfngen_chunks" {
  command = plan

  module {
    source = "./modules/cloud-scanner-role"
  }

  assert {
    condition     = sort(keys(aws_iam_policy.read)) == sort(keys(jsondecode(file("${path.cwd}/tests/fixtures/policy-chunks.json")).account))
    error_message = "The read policies must carry the same bucket numbers as the cfngen chunks."
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_policy.read :
      jsondecode(p.policy).Statement[0].Action == jsondecode(file("${path.cwd}/tests/fixtures/policy-chunks.json")).account[k]
    ])
    error_message = "Every read policy must list the same actions as the cfngen chunk of the same number."
  }
}

# The six spill rounds are fixed: only 1 or 6 buckets are accepted.
run "three_buckets_are_rejected" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["s3:ListAllMyBuckets"]
    buckets = 3
  }

  expect_failures = [var.buckets]
}
