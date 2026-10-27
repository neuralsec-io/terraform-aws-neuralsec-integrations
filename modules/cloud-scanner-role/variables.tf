variable "external_id" {
  description = "ExternalId of the Neuralsec connection. Generated once per connection by cloud-scanner-ctl."
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

variable "eks_clusters" {
  description = "EKS cluster names that get a view-only access entry for this role."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for name in var.eks_clusters : can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,99}$", name))])
    error_message = "eks_clusters must hold valid EKS cluster names."
  }
}
