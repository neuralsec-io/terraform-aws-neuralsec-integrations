variable "external_ids" {
  description = "ExternalId of every Neuralsec CodeArtifact registry that shares this role. The trust policy requires all of them."
  type        = list(string)

  validation {
    condition = length(var.external_ids) > 0 && alltrue([
      for external_id in var.external_ids : can(regex("^neuralsec-[0-9a-f]{32}$", external_id))
    ])
    error_message = "external_ids must hold at least one neuralsec- followed by 32 lowercase hex characters."
  }
}

variable "neuralsec_broker_arn" {
  description = "ARN of the Neuralsec broker role, the only principal allowed to assume this role."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.neuralsec_broker_arn))
    error_message = "neuralsec_broker_arn must be an IAM role ARN."
  }
}

variable "role_name" {
  description = "Name of the role, the one in the registry role ARN."
  type        = string
  default     = "neuralsec-registry-read"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be a valid IAM role name of at most 64 characters."
  }
}

variable "role_path" {
  description = "IAM path of the role, the one in the registry role ARN. Empty means the default path /."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.role_path == "" || can(regex("^/([A-Za-z0-9+=,.@_/-]*/)?$", var.role_path))
    error_message = "role_path must be empty or an IAM path that starts and ends with /."
  }
}

variable "domains" {
  description = "CodeArtifact domains of every sibling registry that shares this role. Each domain gets its domain ARN and its repository ARNs."
  type = list(object({
    region       = string
    domain_owner = string
    domain       = string
  }))

  validation {
    condition = length(var.domains) > 0 && alltrue([
      for domain in var.domains : (
        can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", domain.region)) &&
        can(regex("^[0-9]{12}$", domain.domain_owner)) &&
        can(regex("^[a-z][a-z0-9-]{1,49}$", domain.domain))
      )
    ])
    error_message = "domains must hold at least one valid CodeArtifact domain: region, 12 digit owner and a lowercase domain name."
  }
}
