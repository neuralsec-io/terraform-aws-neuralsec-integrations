variable "external_id" {
  description = "ExternalId of the Neuralsec organization connection. The same value as the member account roles."
  type        = string

  validation {
    condition     = can(regex("^neuralsec-[0-9a-f]{32}$", var.external_id))
    error_message = "external_id must be neuralsec- followed by 32 lowercase hex characters."
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
