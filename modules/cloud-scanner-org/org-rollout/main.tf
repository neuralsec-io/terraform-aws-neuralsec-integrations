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
#   Terraform  gen-org-providers.sh, in this directory, reads aws organizations
#              list-accounts and writes providers.generated.tf with a static
#              aliased provider and module block per active account.
#
# Both paths still read aws_organizations_organization, so a suspended or
# pending closure account is skipped by the state filter, never by a provider
# error, and shows up in skipped_account_ids. The filter reads the account
# `state`, and falls back to the deprecated `status` when a state is absent. The
# management account is never part of the member set: its member access role does
# not exist, so the rollout skips it. Cover it with a standalone
# cloud-scanner-role module and the default provider, see the README.
#
# This root never hands any credential to the scanner. The member access role is
# used only by the customer's own Terraform run, and only to create the scanner
# role. The scanner assumes neuralsec-cloud-scanner through the Neuralsec broker.

terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 7.0"
    }
  }
}

data "aws_organizations_organization" "current" {}

data "aws_partition" "current" {}

locals {
  accounts = {
    for account in data.aws_organizations_organization.current.accounts : account.id => account
  }

  management_account_id = data.aws_organizations_organization.current.master_account_id

  # The account state: `state` when the provider reports it, otherwise the
  # deprecated `status`. Both read ACTIVE, SUSPENDED or PENDING_CLOSURE.
  account_states = {
    for id, account in local.accounts :
    id => try(account.state, null) != null && try(account.state, "") != "" ? account.state : account.status
  }

  requested = toset(var.member_account_ids)
  excluded  = toset(var.exclude_account_ids)

  rollout_accounts = {
    for id, account in local.accounts : id => account
    if contains(local.requested, id) && local.account_states[id] == "ACTIVE" && !contains(local.excluded, id) && id != local.management_account_id
  }

  skipped_account_ids = sort([
    for id, account in local.accounts : id
    if !contains(local.requested, id) || local.account_states[id] != "ACTIVE" || contains(local.excluded, id) || id == local.management_account_id
  ])

  member_role_name = "neuralsec-cloud-scanner"
}

output "member_account_ids" {
  description = "Accounts that receive the read-only scanner role."
  value       = sort(keys(local.rollout_accounts))
}

output "skipped_account_ids" {
  description = "Accounts left out because of state, the management account, exclude_account_ids or member_account_ids."
  value       = local.skipped_account_ids
}

output "management_account_id" {
  description = "The organization management account. It is never given a member role by this root; install the standalone cloud-scanner-role module there."
  value       = local.management_account_id
}

output "member_role_name" {
  description = "Fixed role name created in every member account."
  value       = local.member_role_name
}

output "member_access_role_name" {
  description = "The customer admin role the rollout assumes. Never used by the scanner."
  value       = var.member_access_role_name
}
