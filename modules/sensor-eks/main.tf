# Neuralsec sensor Terraform module for EKS: the chart installed as a Helm
# release.
#
# The chart is the DaemonSet that runs on every Linux node. The module only
# renders the values the chart requires (endpoint, cluster name, image digest,
# security context) and passes the caller's `values` on top, so every other
# chart value stays available without new module inputs.

locals {
  release_name = "neuralsec-sensor"

  # Shallow merge: a nested key in var.values replaces the rendered block as a
  # whole, which keeps the rendered YAML predictable.
  chart_values = merge(
    {
      endpoint    = var.endpoint
      clusterName = var.cluster_name
      image = {
        digest = var.image_digest
      }
      securityContext = {
        privileged = var.privileged
      }
    },
    var.values,
  )
}

resource "helm_release" "sensor" {
  name             = local.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace
  chart            = "neuralsec-sensor"
  repository       = var.chart_repository
  version          = var.chart_version

  values = [yamlencode(local.chart_values)]
}
