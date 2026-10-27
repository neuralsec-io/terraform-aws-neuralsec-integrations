# Organization rollout root.
#
# Apply this from the management account, or from a delegated administrator
# account with permission to assume the member access role, to create the
# read-only scanner role in every active member account.
#
# Two paths exist because provider selection differs:
#
#   OpenTofu   providers.tofu declares one provider instance per account in
#              member_account_ids and one cloud-scanner-role module per ACTIVE account
#              among them, using provider for_each. member_account_ids is
#              required there because provider for_each cannot read a data
#              source. Delete providers.generated.tf before using this path.
#   Terraform  scripts/gen-org-providers.sh reads aws organizations
#              list-accounts and writes providers.generated.tf with a static
#              aliased provider and module block per active account.
#
# Both paths still read aws_organizations_organization, so a suspended or
# pending closure account is skipped by the status filter, never by a provider
# error, and shows up in skipped_account_ids.
#
# This root never hands any credential to the scanner. The member access role is
# used only by the customer's own Terraform run, and only to create the scanner
# role. The scanner assumes neuralsec-cloud-scanner through the Neuralsec broker.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

data "aws_organizations_organization" "current" {}

data "aws_partition" "current" {}

locals {
  accounts = {
    for account in data.aws_organizations_organization.current.accounts : account.id => account
  }

  requested = toset(var.member_account_ids)
  excluded  = toset(var.exclude_account_ids)

  rollout_accounts = {
    for id, account in local.accounts : id => account
    if contains(local.requested, id) && account.status == "ACTIVE" && !contains(local.excluded, id)
  }

  skipped_account_ids = sort([
    for id, account in local.accounts : id
    if !contains(local.requested, id) || account.status != "ACTIVE" || contains(local.excluded, id)
  ])

  member_role_name = "neuralsec-cloud-scanner"
}

output "member_account_ids" {
  description = "Accounts that receive the read-only scanner role."
  value       = sort(keys(local.rollout_accounts))
}

output "skipped_account_ids" {
  description = "Accounts left out because of status, exclude_account_ids or member_account_ids."
  value       = local.skipped_account_ids
}

output "member_role_name" {
  description = "Fixed role name created in every member account."
  value       = local.member_role_name
}

output "member_access_role_name" {
  description = "The customer admin role the rollout assumes. Never used by the scanner."
  value       = var.member_access_role_name
}
