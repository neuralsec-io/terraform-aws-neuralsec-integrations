# Shared policy chunker.
#
# The customer role cannot use action wildcards, so its policy has to list every
# action the scanner uses. IAM caps a policy document at 6144 characters and a
# role at 10 customer managed policies, so this module packs the sorted action
# list into as few documents as the byte budget allows. cloud-scanner-role and
# org-reader turn each document into one aws_iam_policy.

variable "actions" {
  description = "Exact IAM actions to pack into policy documents."
  type        = list(string)
  nullable    = false

  validation {
    condition = alltrue([
      for action in var.actions : can(regex("^[a-z0-9-]+:[A-Za-z0-9]+$", action))
    ])
    error_message = "Every action must look like service:VerbName."
  }

  # Named exceptions, each AWS access level Read and
  # changing no resource: iam:GenerateCredentialReport starts the credential
  # report; apigateway:GET is API Gateway's read action.
  validation {
    condition = alltrue([
      for action in var.actions :
      can(regex("^(List|Describe|Get|BatchGet|Search|Select|Lookup)[A-Za-z0-9]*$", split(":", action)[1]))
      || contains(["iam:GenerateCredentialReport", "apigateway:GET"], action)
    ])
    error_message = "Only read actions are allowed: List, Describe, Get, BatchGet, Search, Select or Lookup, plus the named exceptions iam:GenerateCredentialReport and apigateway:GET."
  }

  # The shared denylist, forbidden-actions.json, is also read by
  # scripts/check-actions.sh and generated into the CloudFormation guard rules by
  # tools/cfngen. Exact names and case-insensitive name patterns that return
  # content or credentials are never allowed.
  validation {
    condition = alltrue([
      for action in var.actions : !contains(
        [for name in jsondecode(file("${path.module}/forbidden-actions.json")).exact : lower(name)],
        lower(action)
      )
    ])
    error_message = "Actions that read customer content or return credentials (object bodies, secret values, parameters, logs, items, messages, image layers, passwords, tokens) are never allowed. See forbidden-actions.json."
  }

  validation {
    condition = alltrue([
      for action in var.actions :
      !can(regex("(?i)(${join("|", jsondecode(file("${path.module}/forbidden-actions.json")).patterns)})", split(":", action)[1]))
      || contains([for name in jsondecode(file("${path.module}/forbidden-actions.json")).pattern_exceptions : lower(name)], lower(action))
    ])
    error_message = "Action names that match a credential or content pattern (Credentials, Password, SecretValue, AuthorizationToken, SessionToken, FederationToken, GetObject, GetRecords, QueryResults) are never allowed. See forbidden-actions.json."
  }
}

variable "max_policy_bytes" {
  description = "Byte budget per document. Keep it below the IAM limit of 6144 characters."
  type        = number
  default     = 5120

  validation {
    condition     = var.max_policy_bytes >= 1000 && var.max_policy_bytes <= 6144
    error_message = "max_policy_bytes must be between 1000 and 6144."
  }
}

locals {
  sorted_actions = sort(distinct(var.actions))

  # Bytes each action adds to a JSON action array: the quoted name plus a comma.
  costs = [for action in local.sorted_actions : length(action) + 4]

  # Start offset of every action in the concatenated array, so the budget cuts
  # the list into consecutive windows and never splits a name.
  offsets = [
    for i in range(length(local.sorted_actions)) :
    try(sum(slice(local.costs, 0, i)), 0)
  ]

  window_index = [for offset in local.offsets : floor(offset / var.max_policy_bytes)]

  chunk_count = length(local.window_index) == 0 ? 0 : max(local.window_index...) + 1

  packed_chunks = [
    for k in range(local.chunk_count) : [
      for i, action in local.sorted_actions : action if local.window_index[i] == k
    ]
  ]

  chunks = [for chunk in local.packed_chunks : chunk if length(chunk) > 0]

  documents = [
    for chunk in local.chunks : jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = chunk
        Resource = "*"
      }]
    })
  ]

  max_document_bytes = length(local.documents) == 0 ? 0 : max([for doc in local.documents : length(doc)]...)

  # Release version stamped on the roles as the neuralsec:integration-version
  # tag. version.json is kept equal to the newest CHANGELOG release by a test,
  # and tools/cfngen stamps the same value into the CloudFormation templates.
  integration_version = jsondecode(file("${path.module}/version.json")).integration_version

  # Resources of the explicit apigateway:GET Deny. apigateway:GET is the one
  # read action that can reach content: API keys, and the exported or SDK
  # bundles of a stage. actions.json may carry its own deny_resources, a list
  # of {action, resources} entries, each one Deny statement; without it the
  # static apigateway:GET list in forbidden-actions.json applies, and
  # tools/cfngen and the CloudFormation guard read the same entries. The ARNs
  # use the aws partition here and the role module swaps in its own.
  deny_resources = try(
    jsondecode(file("${path.module}/actions.json")).deny_resources,
    [{
      action    = "apigateway:GET"
      resources = jsondecode(file("${path.module}/forbidden-actions.json")).deny_resources
    }],
  )
}

output "actions" {
  description = "Sorted, de-duplicated actions that were packed."
  value       = local.sorted_actions
}

output "documents" {
  description = "One IAM policy document per chunk, ready for the policy argument of aws_iam_policy."
  value       = local.documents
}

output "chunk_count" {
  description = "Number of customer managed policies needed. IAM allows at most 10 attached to one role."
  value       = local.chunk_count
}

output "max_document_bytes" {
  description = "Size in bytes of the largest generated document."
  value       = local.max_document_bytes
}

output "integration_version" {
  description = "Release version of this module set, written to the neuralsec:integration-version tag of the scanner roles."
  value       = local.integration_version
}

output "deny_resources" {
  description = "Entries of the explicit Deny, each with an action and its resource ARNs written with the aws partition."
  value       = local.deny_resources
}
