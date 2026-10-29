variable "container_definitions" {
  description = "The task's container definitions as a JSON string."
  type        = string
}

variable "app_containers" {
  description = "Names of the containers to instrument. Other containers are untouched."
  type        = list(string)
}

variable "sidecar_image" {
  description = "Digest-pinned Neuralsec sensor sidecar image (repository@sha256:...)."
  type        = string
  default     = "public.ecr.aws/neuralsec/sensor-ecs"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.sidecar_image))
    error_message = "sidecar_image must be digest-pinned: repository@sha256:<64 hex>."
  }
}

variable "endpoint" {
  description = "Neuralsec sensor endpoint the sidecar reports to."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+", var.endpoint))
    error_message = "endpoint must be an https:// URL."
  }
}

variable "libc" {
  description = "Container name to hook build: glibc, musl or none. Unknown containers default to none."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for build in values(var.libc) : contains(["glibc", "musl", "none"], build)])
    error_message = "libc values must be glibc, musl or none."
  }
}

variable "enable_observer" {
  description = "Run the process observer in the sidecar."
  type        = bool
  default     = true
}

variable "enable_ptrace" {
  description = "Run the event-only ptrace tracer. Adds SYS_PTRACE to the sidecar only."
  type        = bool
  default     = false
}
