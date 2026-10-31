variable "external_id" {
  description = "ExternalId of the Neuralsec organization connection, written into every member role trust policy."
  type        = string

  validation {
    condition     = can(regex("^neuralsec-[0-9a-f]{32}$", var.external_id))
    error_message = "external_id must be neuralsec- followed by 32 lowercase hex characters."
  }
}

variable "neuralsec_broker_arn" {
  description = "ARN of the Neuralsec broker role, the only principal allowed to assume the member roles."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.neuralsec_broker_arn))
    error_message = "neuralsec_broker_arn must be an IAM role ARN."
  }
}

variable "member_access_role_name" {
  description = "The customer's own admin role, assumed only by this Terraform run to create the scanner role in a member account."
  type        = string
  default     = "OrganizationAccountAccessRole"

  validation {
    condition     = can(regex("^[0-9A-Za-z+=,.@_-]{1,64}$", var.member_access_role_name))
    error_message = "member_access_role_name must be a valid IAM role name."
  }
}

variable "member_account_ids" {
  description = "Accounts the rollout manages. Required by the OpenTofu path, where provider for_each cannot read a data source. The plain Terraform path gets its list from scripts/gen-org-providers.sh instead."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.member_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "member_account_ids must hold 12 digit account IDs."
  }
}

variable "exclude_account_ids" {
  description = "Account IDs to leave out of the rollout even when they are ACTIVE."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.exclude_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "exclude_account_ids must hold 12 digit account IDs."
  }
}

variable "state_locations" {
  description = "Terraform or Pulumi state bucket prefixes the scanner may read, applied to every member role. The cloud-scanner-role module validates and encodes them; see its README."
  type = list(object({
    bucket      = string
    prefix      = optional(string, "")
    tool        = optional(string, "terraform")
    region      = optional(string, null)
    kms_key_arn = optional(string, "")
  }))
  default  = []
  nullable = false
}
