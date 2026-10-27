locals {
  policy_name = "neuralsec-codeartifact-read"
  role_path   = var.role_path == "" ? "/" : var.role_path

  # Sort and de-duplicate the domains like the Neuralsec setup instructions do, so the same
  # set of registries always renders the same document.
  domain_arns = sort(distinct([
    for domain in var.domains :
    "arn:${data.aws_partition.current.partition}:codeartifact:${domain.region}:${domain.domain_owner}:domain/${domain.domain}"
  ]))

  # GetRepositoryEndpoint and ReadFromRepository act on the repositories of
  # each domain, not on the domain itself.
  repository_arns = sort(distinct([
    for domain in var.domains :
    "arn:${data.aws_partition.current.partition}:codeartifact:${domain.region}:${domain.domain_owner}:repository/${domain.domain}/*"
  ]))

  # The role is shared on purpose: every Neuralsec CodeArtifact registry that
  # names this role_arn has its own ExternalId, and a template that trusted
  # only one of them would cut off the others. Trust the broker with every
  # sibling ExternalId and nothing else. There is no condition-free fallback.
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.neuralsec_broker_arn }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = sort(distinct(var.external_ids)) } }
    }]
  })

  # Exactly the read actions the broker's Verify and Mint paths call, scoped to
  # the sibling domains and their repositories. Only GetServiceBearerToken
  # uses a wildcard resource: the action supports no resource-level scoping.
  permissions_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "codeartifact:GetAuthorizationToken"
        Resource = local.domain_arns
      },
      {
        Effect   = "Allow"
        Action   = ["codeartifact:GetRepositoryEndpoint", "codeartifact:ReadFromRepository"]
        Resource = local.repository_arns
      },
      {
        Effect    = "Allow"
        Action    = "sts:GetServiceBearerToken"
        Resource  = "*"
        Condition = { StringEquals = { "sts:AWSServiceName" = "codeartifact.amazonaws.com" } }
      },
    ]
  })
}

data "aws_partition" "current" {}

resource "aws_iam_role" "this" {
  name               = var.role_name
  path               = local.role_path
  assume_role_policy = local.trust_policy
}

resource "aws_iam_role_policy" "this" {
  name   = local.policy_name
  role   = aws_iam_role.this.name
  policy = local.permissions_policy
}
