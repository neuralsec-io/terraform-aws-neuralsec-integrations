# Shared policy chunker.
#
# The customer role cannot use action wildcards, so its policy has to list every
# action the scanner uses. IAM caps a policy document at 6144 characters and a
# role at 10 customer managed policies, so this module groups the sorted action
# list by service into at most 6 documents under the byte budget, so that one new
# action touches one policy. cloud-scanner-role and org-reader turn each
# document into one aws_iam_policy.

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
}

variable "buckets" {
  description = "Number of policy buckets, one policy each. The scanner role uses 6, a count that never changes so every service keeps its home policy; a role that carries one small policy uses 1."
  type        = number
  default     = 6

  validation {
    condition     = var.buckets == 1 || var.buckets == 6
    error_message = "buckets must be 1 (the organizations role) or 6 (the scanner role): the six spill rounds are fixed so Terraform and the CloudFormation templates cannot diverge."
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
  forbidden = jsondecode(file("${path.module}/forbidden-actions.json"))

  sorted_actions = sort(distinct(var.actions))

  # Bytes each action adds to a JSON action array: the quoted name plus a comma.
  costs = [for action in local.sorted_actions : length(action) + 4]

  services = [for action in local.sorted_actions : split(":", action)[0]]

  # Actions are assigned to policies by service, never by position, so adding
  # one action changes the one policy that holds its service. There are a fixed
  # number of buckets (6 for the scanner role), one policy each. A service goes to its home bucket,
  # (first 32 bits of md5(service)) mod 6, so every action of one service shares
  # a policy. When a home bucket would pass the byte budget, the services of that
  # bucket, taken in sorted name order, stay while their running total fits and
  # the rest move to the next bucket; this is repeated for 6 rounds so a
  # service can try every bucket. tools/cfngen runs the same rounds, so the
  # CloudFormation templates and this module produce identical policies. An empty
  # bucket creates no policy and the others keep their number: policy names
  # carry the bucket number, so nothing is renumbered.
  bucket_total = var.buckets

  service_names = sort(distinct(local.services))

  service_index = { for i, service in local.service_names : service => i }

  service_bytes = {
    for service in local.service_names :
    service => sum(concat([0], [for i, action in local.sorted_actions : local.costs[i] if local.services[i] == service]))
  }

  assign_0 = {
    for service in local.service_names : service => parseint(substr(md5(service), 0, 8), 16) % local.bucket_total
  }

  assign_1 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_0[other] == local.assign_0[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_0[service] : (local.assign_0[service] + 1) % local.bucket_total
    )
  }

  assign_2 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_1[other] == local.assign_1[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_1[service] : (local.assign_1[service] + 1) % local.bucket_total
    )
  }

  assign_3 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_2[other] == local.assign_2[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_2[service] : (local.assign_2[service] + 1) % local.bucket_total
    )
  }

  assign_4 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_3[other] == local.assign_3[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_3[service] : (local.assign_3[service] + 1) % local.bucket_total
    )
  }

  assign_5 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_4[other] == local.assign_4[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_4[service] : (local.assign_4[service] + 1) % local.bucket_total
    )
  }

  assign_6 = {
    for service in local.service_names : service => (
      sum(concat([0], [
        for other in local.service_names : local.service_bytes[other]
        if local.assign_5[other] == local.assign_5[service] && local.service_index[other] <= local.service_index[service]
      ])) <= var.max_policy_bytes ? local.assign_5[service] : (local.assign_5[service] + 1) % local.bucket_total
    )
  }

  bucket_of = local.assign_6

  packed_chunks = [
    for k in range(local.bucket_total) : [
      for i, action in local.sorted_actions : action if local.bucket_of[local.services[i]] == k
    ]
  ]

  # Bucket numbers (1 to 6) of the non-empty chunks, in order: the policy names.
  chunk_numbers = [for k, chunk in local.packed_chunks : k + 1 if length(chunk) > 0]

  chunks = [for chunk in local.packed_chunks : chunk if length(chunk) > 0]

  chunk_count = length(local.chunks)

  max_chunk_bytes = length(local.chunks) == 0 ? 0 : max([for chunk in local.chunks : sum([for action in chunk : length(action) + 4])]...)

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

  # The shared denylist, forbidden-actions.json, is also read by
  # scripts/check-actions.sh and generated into the CloudFormation guard rules by
  # tools/cfngen. Exact names and case-insensitive name patterns that return
  # content or credentials are never allowed. A variable validation cannot read
  # a file on Terraform 1.4, so the check lives on this output, which every
  # caller evaluates.
  precondition {
    condition = alltrue([
      for action in var.actions : !contains(
        [for name in local.forbidden.exact : lower(name)],
        lower(action)
      )
    ])
    error_message = "Actions that read customer content or return credentials (object bodies, secret values, parameters, logs, items, messages, image layers, passwords, tokens) are never allowed. See forbidden-actions.json."
  }

  precondition {
    condition = alltrue([
      for action in var.actions :
      !can(regex("(?i)(${join("|", local.forbidden.patterns)})", split(":", action)[1]))
      || contains([for name in local.forbidden.pattern_exceptions : lower(name)], lower(action))
    ])
    error_message = "Action names that match a credential or content pattern (Credentials, Password, SecretValue, AuthorizationToken, SessionToken, FederationToken, GetObject, GetRecords, QueryResults) are never allowed. See forbidden-actions.json."
  }

  precondition {
    condition     = local.max_chunk_bytes <= var.max_policy_bytes
    error_message = "Spill overflow: a service moves only to the next of the ${local.bucket_total} policies and each service is tried in at most six rounds, and the action list still does not fit ${local.bucket_total} policies of ${var.max_policy_bytes} bytes when grouped by service (the role holds at most 10 managed policies, two of them the deny and IaC state policies). The largest policy would be ${local.max_chunk_bytes} bytes."
  }
}

output "chunk_numbers" {
  description = "Bucket number (1 to 6) of every policy document, in order. Policy names carry it, so an empty bucket leaves a gap instead of renumbering."
  value       = local.chunk_numbers
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
