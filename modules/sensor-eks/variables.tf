variable "endpoint" {
  description = "The Neuralsec sensor endpoint the pods report to. Must be an https:// URL; rendered as endpoint."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+", var.endpoint))
    error_message = "endpoint must be an https:// URL."
  }
}

variable "cluster_name" {
  description = "The cluster name reported with the sensor's node metadata. Rendered as clusterName."
  type        = string
}

variable "image_digest" {
  description = "Digest of the sensor image, sha256: followed by 64 lowercase hex characters. Rendered as image.digest."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "image_digest must be sha256: followed by 64 lowercase hex characters."
  }
}

variable "chart_version" {
  description = "Version of the neuralsec-sensor chart to install."
  type        = string
  default     = "0.1.0"
}

variable "chart_repository" {
  description = "OCI repository holding the chart."
  type        = string
  default     = "oci://public.ecr.aws/neuralsec/charts"
}

variable "namespace" {
  description = "Namespace the release is installed into."
  type        = string
  default     = "neuralsec"
}

variable "create_namespace" {
  description = "Create the namespace when it does not exist."
  type        = bool
  default     = true
}

variable "values" {
  description = "Extra chart values, merged last over the values rendered from the inputs. A nested key replaces the whole rendered block."
  type        = any
  default     = {}
}

variable "privileged" {
  description = "Run the sensor pod privileged for node images that refuse a capability-only pod. Rendered as securityContext.privileged."
  type        = bool
  default     = false
}
