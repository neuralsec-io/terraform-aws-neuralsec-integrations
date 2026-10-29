variable "endpoint" {
  description = "The Neuralsec sensor endpoint the sensor reports to. Must be an https:// URL; set as RUNTIME_SENSOR_ENDPOINT in the unit."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+", var.endpoint))
    error_message = "endpoint must be an https:// URL."
  }
}

variable "sensor_version" {
  description = "Sensor build version to install, the directory under artifact_base_url."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z._-]+$", var.sensor_version))
    error_message = "sensor_version must contain only letters, digits, dots, underscores and hyphens."
  }
}

variable "sha256" {
  description = "Expected sha256 of the release tarball per architecture, as 64 lowercase hex characters."
  type        = map(string)

  validation {
    condition = (
      contains(keys(var.sha256), "x86_64")
      && contains(keys(var.sha256), "aarch64")
      && alltrue([for arch in ["x86_64", "aarch64"] : can(regex("^[0-9a-f]{64}$", lookup(var.sha256, arch, "")))])
    )
    error_message = "sha256 must map both x86_64 and aarch64 to 64 lowercase hex characters."
  }
}

variable "artifact_base_url" {
  description = "Base URL of the release artifacts. The tarball is fetched from <artifact_base_url>/<sensor_version>/neuralsec-sensor-linux-<arch>.tar.gz."
  type        = string
  default     = "https://downloads.neuralsec.io/sensor"

  validation {
    condition     = can(regex("^https://[^/]+", var.artifact_base_url))
    error_message = "artifact_base_url must be an https:// URL."
  }
}

variable "targets" {
  description = "SSM association targets. Each entry is one target: key and an ordered list of values. The default selects instances tagged neuralsec-sensor=enabled."
  type = list(object({
    key    = string
    values = list(string)
  }))
  default = [
    {
      key    = "tag:neuralsec-sensor"
      values = ["enabled"]
    },
  ]
}

variable "schedule" {
  description = "Schedule expression for the association."
  type        = string
  default     = "rate(30 minutes)"
}

variable "uninstall" {
  description = "Render the document that stops, disables and removes the sensor instead of installing it."
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix for the SSM document name."
  type        = string
  default     = "neuralsec-sensor"
}
