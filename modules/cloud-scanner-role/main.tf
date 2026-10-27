locals {
  role_name = "neuralsec-cloud-scanner"

  actions = jsondecode(file("${path.module}/../policy/actions.json")).account

  # The scanner uses no static credentials and no other principal may assume the
  # customer role, so the trust policy names the broker and requires the
  # connection ExternalId. There is no condition-free fallback.
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

  # Group the access entry places the role in. The ClusterRoleBinding in
  # kubernetes/scanner-rbac-view.yaml binds this group to a read-only RBAC
  # ClusterRole, because AmazonEKSViewPolicy does not cover
  # rbac.authorization.k8s.io and AmazonEKSAdminViewPolicy can read Secrets.
  eks_rbac_group = "neuralsec:scanner-rbac-view"

  eks_view_policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
}

data "aws_partition" "current" {}

module "policy" {
  source = "../policy"

  actions = local.actions
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "Neuralsec read-only cloud inventory role. Assumed through the Neuralsec broker with the connection ExternalId."
  assume_role_policy   = local.trust_policy
  max_session_duration = 3600
}

resource "aws_iam_policy" "read" {
  count = module.policy.chunk_count

  name        = "${local.role_name}-read-${format("%02d", count.index + 1)}"
  description = "Neuralsec cloud scanner read actions, part ${count.index + 1} of ${module.policy.chunk_count}."
  policy      = module.policy.documents[count.index]
}

resource "aws_iam_role_policy_attachment" "read" {
  count = length(aws_iam_policy.read)

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.read[count.index].arn
}

resource "aws_eks_access_entry" "this" {
  for_each = toset(var.eks_clusters)

  cluster_name  = each.value
  principal_arn = aws_iam_role.this.arn
  type          = "STANDARD"

  kubernetes_groups = [local.eks_rbac_group]
}

resource "aws_eks_access_policy_association" "this" {
  for_each = toset(var.eks_clusters)

  cluster_name  = each.value
  principal_arn = aws_iam_role.this.arn
  policy_arn    = local.eks_view_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.this]
}

# IAM rejects an eleventh attached managed policy and a document over 6144
# characters. Fail at plan time with a readable message instead of an API error
# half way through a customer apply.
resource "terraform_data" "policy_guard" {
  input = {
    chunks             = module.policy.chunk_count
    max_document_bytes = module.policy.max_document_bytes
  }

  lifecycle {
    precondition {
      condition     = module.policy.chunk_count <= 10
      error_message = "The exported action list needs ${module.policy.chunk_count} managed policies, but IAM allows at most 10 per role."
    }

    precondition {
      condition     = module.policy.max_document_bytes <= 6144
      error_message = "A generated policy document is ${module.policy.max_document_bytes} bytes, over the IAM limit of 6144."
    }
  }
}
