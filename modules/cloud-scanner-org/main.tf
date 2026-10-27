locals {
  role_name = "neuralsec-cloud-scanner-org-reader"

  actions = jsondecode(file("${path.module}/../policy/actions.json")).org_reader

  # Organizations read actions only, so the org reader sees the tree, the
  # accounts and the policies without reaching into any member account.
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "NeuralsecBrokerAssumeRoleWithExternalId"
      Effect    = "Allow"
      Action    = ["sts:AssumeRole"]
      Principal = { AWS = var.neuralsec_broker_arn }
      Condition = { StringEquals = { "sts:ExternalId" = var.external_id } }
    }]
  })
}

module "policy" {
  source = "../policy"

  actions = local.actions
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "Neuralsec read-only AWS Organizations role for the management or delegated administrator account."
  assume_role_policy   = local.trust_policy
  max_session_duration = 3600
}

resource "aws_iam_policy" "read" {
  count = module.policy.chunk_count

  name        = "${local.role_name}-read-${format("%02d", count.index + 1)}"
  description = "Neuralsec organizations read actions, part ${count.index + 1} of ${module.policy.chunk_count}."
  policy      = module.policy.documents[count.index]
}

resource "aws_iam_role_policy_attachment" "read" {
  count = length(aws_iam_policy.read)

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.read[count.index].arn
}

resource "terraform_data" "policy_guard" {
  input = {
    chunks             = module.policy.chunk_count
    max_document_bytes = module.policy.max_document_bytes
  }

  lifecycle {
    precondition {
      condition     = module.policy.chunk_count <= 10
      error_message = "The exported org_reader action list needs ${module.policy.chunk_count} managed policies, but IAM allows at most 10 per role."
    }

    precondition {
      condition     = module.policy.max_document_bytes <= 6144
      error_message = "A generated policy document is ${module.policy.max_document_bytes} bytes, over the IAM limit of 6144."
    }
  }
}
