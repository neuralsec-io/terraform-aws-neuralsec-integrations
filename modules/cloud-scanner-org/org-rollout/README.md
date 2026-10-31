# org-rollout

Applies the read-only scanner role to every account in an AWS Organization.

Each member account gets `terraform/modules/cloud-scanner-role`: role
`neuralsec-cloud-scanner`, trusted only by the Neuralsec broker role with the
connection ExternalId. The role holds the read actions of the Neuralsec scanner's action list
(`terraform/modules/policy/actions.json`), split
across several customer managed policies so no document passes the IAM size
limit.

## The scanner never uses your admin role

`member_access_role_name` (`OrganizationAccountAccessRole` by default) is assumed
only by your own Terraform run, and only to create the scanner role in a member
account. The scanner itself never assumes it, never reads its credentials, and
has no path to it: the scanner role trusts only `neuralsec-cloud-scanner-broker`,
which may only assume roles named `neuralsec-cloud-scanner` or
`neuralsec-cloud-scanner-org-reader`. Nothing in this root is handed to
Neuralsec.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `external_id` | string | required | Connection ExternalId, `neuralsec-` plus 32 hex characters |
| `neuralsec_broker_arn` | string | required | ARN of the Neuralsec broker role |
| `member_access_role_name` | string | `OrganizationAccountAccessRole` | Your admin role, used only by this Terraform run |
| `member_account_ids` | list(string) | `[]` | Accounts the rollout manages. Required by the OpenTofu path |
| `exclude_account_ids` | list(string) | `[]` | Accounts to leave out even when ACTIVE |
| `state_locations` | list(object) | `[]` | IaC state bucket prefixes every member role may read, passed to `cloud-scanner-role` unchanged |

Accounts reported `SUSPENDED` or `PENDING_CLOSURE` by
`aws_organizations_organization` are never given a role and are listed in the
`skipped_account_ids` output, so a closed account cannot fail an apply. An empty
`member_account_ids` is a valid no-op: it creates no provider instance and no
module, and every organization account is reported as skipped.

## OpenTofu path

OpenTofu reads `providers.tofu`, which declares one provider instance per account
with provider `for_each` and one `cloud-scanner-role` module per ACTIVE account.
A provider `for_each` cannot read a data source, so the account list comes in as
`member_account_ids`. Get it with a read-only call:

```
aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE`].Id' --output json
```

Then, from this directory:

```
tofu init
tofu plan -var 'external_id=neuralsec-...' \
  -var 'neuralsec_broker_arn=arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker' \
  -var 'member_account_ids=["111111111111","222222222222"]'
```

Remove `providers.generated.tf` first if a previous plain Terraform run wrote it:
OpenTofu refuses to run while it exists, because both paths would create the same
roles twice.

## Plain Terraform path

Terraform has no provider `for_each`, so `scripts/gen-org-providers.sh` reads the
organization with `aws organizations list-accounts` and writes
`providers.generated.tf`: one aliased provider and one `cloud-scanner-role` module
block per ACTIVE account. The file is not committed (it is in `.gitignore`),
because it holds your account IDs.

From the repository root:

```
bash scripts/gen-org-providers.sh
cd terraform/modules/cloud-scanner-org/org-rollout
terraform init
terraform plan -var 'external_id=neuralsec-...' \
  -var 'neuralsec_broker_arn=arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker'
```

Options: `--accounts <file>` for a saved `list-accounts` JSON instead of the CLI,
`--out <file>`, `--role-name`, `--partition`, `--exclude <id,id>`.

Both paths report `member_role_arns` keyed by account ID.

## Tests

```
# from terraform/
terraform test
tofu test

# from the repository root
bash scripts/test-gen-org-providers.sh                # generator output validates
```

Both engines run the same assertions from different files, because the
configuration they load is different:

- `terraform/tests/org_rollout.tftest.hcl` is the plain Terraform run. Terraform
  ignores `providers.tofu`, so it sees no per-account provider instance and no
  `cloud-scanner-role` module.
- `terraform/tests/org_rollout.tofutest.hcl` is the OpenTofu run. It mocks the
  provider instances `providers.tofu` declares (`mock_provider` with `for_each` is
  OpenTofu only) and asserts on the module instances as well as the filter
  outputs.

OpenTofu loads the `.tofutest.hcl` in preference to the `.tftest.hcl` with the
same base name, and Terraform ignores `.tofutest.hcl`, so neither engine runs a
variant written for the other. The module-local OpenTofu test lives in
`terraform/modules/cloud-scanner-org/org-rollout/tests/` for the same reason.

## Removing the rollout

Destroy with the same path that applied it, before removing accounts from the
input list: a provider instance has to outlive the module instance that used it.
Keep suspended accounts in `member_account_ids` until their module instance is
destroyed.
