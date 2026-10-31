# OpenTofu only path. Plain Terraform ignores .tofu files, so
# providers.generated.tf takes over there instead.
#
# The provider for_each holds every requested account, including the ones the
# status filter skips. A provider instance must outlive the module instance that
# used it, otherwise a later plan cannot destroy a role for an account that was
# suspended or excluded in the meantime. Only active accounts get a module
# instance, so a suspended account is skipped by a filter, never by a provider
# error.
#
# provider for_each cannot read a data source, which is why the account list
# comes in as member_account_ids. An empty list is a valid no-op: it creates no
# provider instance and no module, which is what the filter reports as an empty
# rollout. It is not an error, so a plan-only test can assert that behaviour.

provider "aws" {
  alias    = "member"
  for_each = local.requested

  assume_role {
    role_arn     = "arn:${data.aws_partition.current.partition}:iam::${each.key}:role/${var.member_access_role_name}"
    session_name = "neuralsec-cloud-scanner-rollout"
  }
}

module "member_role" {
  source   = "../../cloud-scanner-role"
  for_each = local.rollout_accounts

  providers = {
    aws = aws.member[each.key]
  }

  external_id          = var.external_id
  neuralsec_broker_arn = var.neuralsec_broker_arn
  state_locations      = var.state_locations
}

output "member_role_arns" {
  description = "Scanner role ARN per member account."
  value       = { for account_id, role in module.member_role : account_id => role.role_arn }
}

# The generated file and this path would create the same roles twice.
resource "terraform_data" "open_tofu_path_guard" {
  lifecycle {
    precondition {
      condition     = !fileexists("${path.module}/providers.generated.tf")
      error_message = "providers.generated.tf is the plain Terraform path. Delete it before running OpenTofu."
    }
  }
}
