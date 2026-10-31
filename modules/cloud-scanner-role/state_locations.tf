# IaC state locations: the one exception to the no-object-contents rule.
#
# The scanner never reads object bodies, with one exception: the Terraform and
# Pulumi state objects at the bucket prefixes the customer registers here. This
# input is authoritative in both directions. It is the read grant, because the
# role gets s3:GetObject on exactly these object ARNs and kms:Decrypt on exactly
# the keys listed, and it is the discovery signal: the role carries one numbered
# tag per location, which is how Neuralsec learns which locations the module
# actually granted. A location typed in the console is a suggestion and is never
# read until it appears in this input.
#
# The state actions live outside the shared chunker on purpose. The chunker
# rejects s3:GetObject and kms:Decrypt by name, and that rejection stays in
# place: the account read policy can never carry them, and only this scoped
# policy does. The plan test pins the actions here to the `iac_state` set of the
# published action list, so a change on either side fails a test instead of
# drifting. Neuralsec reads the tags with an action the account policy already
# grants (iam:GetAccountAuthorizationDetails), so this policy needs no IAM action
# of its own.

locals {
  state_locations_enabled = length(var.state_locations) > 0

  # The provider's region. Both the 5.x and the 6.x AWS provider export it as
  # name, so this stays valid across the range the module supports.
  provider_region = data.aws_region.current.name

  # The resolved region per location: the explicit one, or the provider's. The
  # scanner reads the bucket in this region, so it never has to guess an
  # endpoint, and the tag records the same value the policy was built from.
  state_location_regions = [
    for loc in var.state_locations : coalesce(loc.region, local.provider_region)
  ]

  # One record per location: tool, region, bucket and prefix joined by a newline
  # and encoded as standard base64. This string is decoded by Neuralsec to learn
  # the authoritative locations, so it is part of the module contract.
  #
  # Base64 is not a style choice. IAM accepts only [\p{L}\p{Z}\p{N}_.:/=+\-@] in
  # a tag value, so a separator or a percent escape cannot be part of the value:
  # the earlier "tool|region|bucket|prefix" form failed TagRole and no apply
  # landed. Base64 stays inside that set for every byte. The KMS key is not in
  # the tag: S3 decrypts state objects server side, so the scanner never needs
  # the key ARN, and this policy still grants kms:Decrypt on it.
  state_location_records = [
    for i, loc in var.state_locations : base64encode(join("\n", [
      loc.tool,
      local.state_location_regions[i],
      loc.bucket,
      loc.prefix,
    ]))
  ]

  # One tag per location, numbered from 1. IAM caps a tag value at 256
  # characters, and the guard below fails the plan instead of letting an apply
  # die half way through. Removing a location removes its tag; renumbering only
  # happens when a middle entry is removed, and the values stay authoritative
  # because Neuralsec reads them by key suffix, not by position.
  state_location_tags = {
    for i, record in local.state_location_records : "neuralsec:state-locations-${i + 1}" => record
  }

  state_bucket_arns = distinct([
    for loc in var.state_locations : "arn:${data.aws_partition.current.partition}:s3:::${loc.bucket}"
  ])

  # Only objects under the registered prefix: the grant is the prefix plus
  # everything below it, never the bucket.
  state_object_arns = [
    for loc in var.state_locations : "arn:${data.aws_partition.current.partition}:s3:::${loc.bucket}/${loc.prefix}*"
  ]

  # One s3:ListBucket statement per bucket, conditioned on that bucket's
  # prefixes and their children, so listing a prefix the customer did not
  # register is denied even inside a registered bucket and a prefix of one
  # bucket can never condition another.
  state_list_statements = [
    for i, bucket in local.state_bucket_arns : {
      Sid      = "IacStateListRegisteredPrefixes${i + 1}"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [bucket]
      Condition = {
        StringLike = {
          "s3:prefix" = distinct(flatten([
            for loc in var.state_locations :
            [loc.prefix, "${loc.prefix}*"]
            if "arn:${data.aws_partition.current.partition}:s3:::${loc.bucket}" == bucket
          ]))
        }
      }
    }
  ]

  state_kms_key_arns = distinct([
    for loc in var.state_locations : loc.kms_key_arn if loc.kms_key_arn != ""
  ])

  # Only the regions of the locations that carry a key: the condition is the
  # S3 endpoint that may call kms:Decrypt, never the endpoint of a location
  # without one.
  state_kms_via_service = distinct([
    for i, loc in var.state_locations : "s3.${local.state_location_regions[i]}.amazonaws.com"
    if loc.kms_key_arn != ""
  ])

  state_policy_statements = concat(
    local.state_list_statements,
    [
      {
        Sid      = "IacStateGetRegisteredObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = local.state_object_arns
      },
    ],
    length(local.state_kms_key_arns) == 0 ? [] : [
      {
        Sid      = "IacStateDecryptRegisteredKeys"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = local.state_kms_key_arns
        Condition = {
          StringEquals = { "kms:ViaService" = local.state_kms_via_service }
        }
      },
    ],
  )

  state_policy_document = jsonencode({
    Version   = "2012-10-17"
    Statement = local.state_policy_statements
  })
}

data "aws_region" "current" {}

resource "aws_iam_policy" "iac_state" {
  count = local.state_locations_enabled ? 1 : 0

  name        = "${local.role_name}-iac-state"
  description = "Neuralsec cloud scanner IaC state reads, scoped to the bucket prefixes the customer registered."
  policy      = local.state_policy_document
}

resource "aws_iam_role_policy_attachment" "iac_state" {
  count = length(aws_iam_policy.iac_state)

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.iac_state[count.index].arn
}

# Fails the plan with a readable message instead of an IAM error on apply: the
# encoded tag has to fit one tag value, and a role can carry at most 50 tags.
# The resource only exists once a location is registered, so a role with an
# empty input plans no new object at all.
resource "terraform_data" "state_location_guard" {
  count = local.state_locations_enabled ? 1 : 0

  input = local.state_location_tags

  lifecycle {
    precondition {
      condition = alltrue([
        for key, value in local.state_location_tags : length(value) <= 256
      ])
      error_message = "A state_locations entry encodes to more than the 256 character IAM tag value limit; shorten the prefix or the bucket name."
    }

    precondition {
      condition     = length(local.state_location_tags) <= 50
      error_message = "state_locations holds ${length(local.state_location_tags)} entries, but a role can carry at most 50 tags."
    }
  }
}
