variable "external_id" {
  description = "ExternalId of the Neuralsec connection. Generated once per connection by Neuralsec."
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

variable "state_locations" {
  description = "Terraform or Pulumi state bucket prefixes the scanner may read. This input is the read grant: the role gets s3:GetObject on exactly these prefixes, and kms:Decrypt on the keys listed here. It is also what tells Neuralsec which locations are authoritative, so a location typed in the console is never read until it is added here. The module can see only its own tags: a provider default_tags block also tags this role and counts toward the 50 tag limit."
  type = list(object({
    bucket      = string
    prefix      = optional(string, "")
    tool        = optional(string, "terraform")
    region      = optional(string, null)
    kms_key_arn = optional(string, "")
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for loc in var.state_locations : can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", loc.bucket))])
    error_message = "state_locations bucket must be an S3 bucket name: lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition = alltrue([
      for loc in var.state_locations :
      length(loc.bucket) >= 3 && length(loc.bucket) <= 63 && !can(regex("[.]{2}", loc.bucket)) && !startswith(loc.bucket, "xn--") && !can(regex("(-s3alias|--ol-s3)$", loc.bucket)) && !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", loc.bucket))
    ])
    error_message = "state_locations bucket must be between 3 and 63 characters, must not contain \"..\", must not look like an IP address or an S3 alias, and must not start with xn--."
  }

  validation {
    condition = alltrue([
      for loc in var.state_locations :
      length(loc.prefix) <= 1024 &&
      !startswith(loc.prefix, "/") &&
      !strcontains(loc.prefix, "*") &&
      !strcontains(loc.prefix, "?") &&
      !strcontains(loc.prefix, "$${")
    ])
    error_message = "state_locations prefix must be at most 1024 characters, must not start with a slash (S3 keys never do) and must be a literal prefix: no wildcard characters and no template markers."
  }

  validation {
    condition     = alltrue([for loc in var.state_locations : contains(["terraform", "pulumi"], loc.tool)])
    error_message = "state_locations tool must be terraform or pulumi."
  }

  validation {
    condition = alltrue([
      for loc in var.state_locations :
      loc.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", loc.region))
    ])
    error_message = "state_locations region must be an AWS region name or null to use the provider region."
  }

  validation {
    condition = alltrue([
      for loc in var.state_locations :
      loc.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9/_-]+$", loc.kms_key_arn))
    ])
    error_message = "state_locations kms_key_arn must be empty or a KMS key ARN (arn:...:key/<id>), never an alias ARN: kms:Decrypt is evaluated against the key, so an alias would grant nothing."
  }

  validation {
    condition     = length(var.state_locations) <= 50
    error_message = "state_locations holds ${length(var.state_locations)} entries, over the 50 tag limit IAM allows on one role."
  }

  validation {
    condition     = length(distinct([for loc in var.state_locations : "${loc.bucket}/${loc.prefix}"])) == length(var.state_locations)
    error_message = "state_locations must not list the same bucket and prefix twice: one prefix is read once."
  }
}
