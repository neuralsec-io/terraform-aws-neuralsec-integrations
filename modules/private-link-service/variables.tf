variable "name" {
  description = "Name of the private link. It is used in the resource names and in the Name tag. Letters, digits and hyphens, at most 19 characters, not starting or ending with a hyphen."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,17}[A-Za-z0-9])?$", var.name))
    error_message = "name must be 1 to 19 letters, digits or hyphens, starting and ending with a letter or digit: load balancer names cannot end in a hyphen."
  }
}

variable "neuralsec_org_id" {
  description = "Neuralsec organization UUID. The module tags every resource with it as neuralsec:org_id."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.neuralsec_org_id))
    error_message = "neuralsec_org_id must be a lowercase UUID."
  }
}

variable "neuralsec_org_slug" {
  description = "Neuralsec organization slug. The module tags every resource with it as neuralsec:org_slug."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.neuralsec_org_slug))
    error_message = "neuralsec_org_slug must be 2 to 63 lowercase letters, digits or hyphens."
  }
}

variable "neuralsec_principal_arn" {
  description = "ARN of the Neuralsec role that is the only principal allowed to connect to the endpoint service."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.neuralsec_principal_arn))
    error_message = "neuralsec_principal_arn must be an IAM role ARN."
  }
}

variable "neuralsec_region" {
  description = "Region of the Neuralsec consumer. The endpoint service advertises it as a supported region when it differs from the region of this stack."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.neuralsec_region))
    error_message = "neuralsec_region must be an AWS region name such as eu-west-1."
  }
}

variable "vpc_id" {
  description = "VPC that holds the service and the private subnets the load balancer uses."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC id."
  }
}

variable "subnet_ids" {
  description = "Private subnets the load balancer uses. Give one subnet in each of at least two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for subnet_id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", subnet_id))])
    error_message = "subnet_ids must hold at least two subnet ids."
  }
}

variable "target_ips" {
  description = "Private IPv4 addresses of the service to register as targets. Set exactly one of target_ips and target_instance_ids unless existing_nlb_arn is set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.target_ips : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))])
    error_message = "target_ips must hold IPv4 addresses."
  }
}

variable "target_instance_ids" {
  description = "Instance ids to register as targets. Set exactly one of target_ips and target_instance_ids unless existing_nlb_arn is set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for instance_id in var.target_instance_ids : can(regex("^i-[0-9a-f]{8,17}$", instance_id))])
    error_message = "target_instance_ids must hold instance ids."
  }
}

variable "target_port" {
  description = "TCP port of the targets. The listener stays on 443, because Neuralsec connects over HTTPS only."
  type        = number
  default     = 443

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "target_port must be a TCP port between 1 and 65535."
  }
}

variable "acceptance_required" {
  description = "Whether a connection request to the endpoint service needs your acceptance. The allowed principal already limits the consumers to Neuralsec, so the default accepts automatically."
  type        = bool
  default     = false
}

variable "existing_nlb_arn" {
  description = "ARN of an existing internal Network Load Balancer to publish. When set, the module creates only the endpoint service and skips the load balancer, target group, listener and security group."
  type        = string
  default     = null

  validation {
    condition     = var.existing_nlb_arn == null || can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/net/.+$", var.existing_nlb_arn))
    error_message = "existing_nlb_arn must be the ARN of a Network Load Balancer."
  }
}

variable "tags" {
  description = "Additional tags for every resource the module creates."
  type        = map(string)
  default     = {}
}
