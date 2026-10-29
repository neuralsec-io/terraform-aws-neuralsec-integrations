output "namespace" {
  description = "Namespace the release is installed into."
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name."
  value       = local.release_name
}

output "chart_version" {
  description = "Chart version installed."
  value       = var.chart_version
}
