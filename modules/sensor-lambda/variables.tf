variable "environment" {
  description = "The function's current environment variables. The module returns the desired map; the caller passes it to aws_lambda_function."
  type        = map(string)
  default     = {}
}

variable "layers" {
  description = "The function's current layer ARNs, in order. Sensor layers for any region, architecture or version are replaced in place."
  type        = list(string)
  default     = []
}

variable "architecture" {
  description = "The function's instruction set architecture."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be one of: x86_64, arm64."
  }
}

variable "runtime" {
  description = "The function's runtime identifier, for example python3.12. A provided.* runtime defaults to preload mode and warns that the hook cannot load into it."
  type        = string
  default     = null
}

variable "package_type" {
  description = "The function's package type. Layers do not apply to Image; the module then returns the Dockerfile lines instead."
  type        = string
  default     = "Zip"

  validation {
    condition     = contains(["zip", "image"], lower(var.package_type))
    error_message = "package_type must be Zip or Image."
  }
}

variable "region" {
  description = "The function's AWS region, used to look the sensor layer ARN up in layers.json."
  type        = string
}

variable "endpoint" {
  description = "The Neuralsec sensor endpoint the function reports to. Must be an https:// URL; returned as RUNTIME_SENSOR_ENDPOINT."
  type        = string

  validation {
    condition     = startswith(var.endpoint, "https://")
    error_message = "endpoint must start with https://."
  }
}

variable "mode" {
  description = "How the hook is injected. Defaults to wrapper for managed runtimes and preload for provided.*."
  type        = string
  default     = null

  validation {
    condition     = var.mode == null ? true : contains(["wrapper", "preload"], var.mode)
    error_message = "mode must be wrapper or preload, or null."
  }
}

variable "libc" {
  description = "Hook libc variant used by preload mode."
  type        = string
  default     = "glibc"

  validation {
    condition     = contains(["glibc", "musl"], var.libc)
    error_message = "libc must be glibc or musl."
  }
}

variable "egress_proxy" {
  description = "Opt the function into the extension's egress proxy. Refused if the function already defines proxy variables the sensor will not chain to."
  type        = bool
  default     = false
}
