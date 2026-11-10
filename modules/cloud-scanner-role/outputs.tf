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

output "scanner_egress_ipv6_cidrs" {
  description = "IPv6 /56 the scanner connects from, for a dual-stack (ipv6) cluster created after October 2024. Allow it together with scanner_egress_ipv4_cidrs, because the scanner prefers IPv6 and falls back to IPv4. EKS rejects IPv6 CIDRs on any other cluster."
  value       = local.scanner_egress_ipv6_cidrs
}

output "scanner_egress_ipv4_cidrs" {
  description = "Fixed IPv4 addresses the scanner connects from, one /32 each. Allow them in vpc_config.public_access_cidrs on every cluster: an IPv4 cluster, an ipv6 cluster created before October 2024 and a dual-stack cluster created after October 2024."
  value       = local.scanner_egress_ipv4_cidrs
}

output "scanner_egress_cidrs" {
  description = "Both egress families, IPv6 first. A dual-stack (ipv6) cluster created after October 2024 accepts this whole list in vpc_config.public_access_cidrs; every other cluster takes scanner_egress_ipv4_cidrs."
  value       = local.scanner_egress_cidrs
}

output "iac_state_policy_document" {
  description = "Rendered IaC state policy (s3:ListBucket, s3:GetObject and, when a key is registered, kms:Decrypt), or an empty string when no state location is registered. Exposed for the policy test."
  value       = local.state_locations_enabled ? local.state_policy_document : ""
}

output "state_location_tags" {
  description = "Tags set on the role to publish the authoritative IaC state locations, one numbered tag per location. Exposed for the policy test."
  value       = local.state_location_tags
}
