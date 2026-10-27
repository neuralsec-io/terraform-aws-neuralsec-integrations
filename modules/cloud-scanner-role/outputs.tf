output "role_arn" {
  description = "ARN of the read-only scanner role in this account."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Fixed role name the scanner assumes in this account."
  value       = aws_iam_role.this.name
}

output "policy_documents" {
  description = "Generated policy documents, one per chunk. Exposed for the policy test."
  value       = module.policy.documents
}

output "policy_chunk_count" {
  description = "Number of customer managed policies attached to the role. Exposed for the policy test."
  value       = module.policy.chunk_count
}

output "policy_max_document_bytes" {
  description = "Size of the largest policy document. Exposed for the policy test."
  value       = module.policy.max_document_bytes
}

output "trust_policy" {
  description = "Rendered trust policy. Exposed for the policy test."
  value       = local.trust_policy
}

output "eks_rbac_group" {
  description = "Kubernetes group set on the EKS access entries. Bind it with kubernetes/scanner-rbac-view.yaml in every cluster."
  value       = local.eks_rbac_group
}

output "eks_rbac_manifest_path" {
  description = "Path of the read-only RBAC ClusterRole and ClusterRoleBinding manifest to kubectl apply in every cluster."
  value       = "${path.module}/kubernetes/scanner-rbac-view.yaml"
}
