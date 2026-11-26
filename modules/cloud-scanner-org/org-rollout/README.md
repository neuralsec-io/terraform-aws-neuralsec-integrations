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
| `state_locations` | list(object) | `[]` | IaC state bucket prefixes every member role may read, passed to `cloud-scanner-role` unchanged. Each member role limits its S3 grants to buckets owned by its own account: for a central state bucket in another account set `bucket_owner` to that account id on the location, or the scanner cannot read it. |

Only accounts whose state is `ACTIVE` are given a role. The state is read from the
account `state`, and from the deprecated `status` when an account reports no state
(provider 6.x exposes `state`; provider 5.x reports only `status`, which the
filter falls back to). Accounts reported
`SUSPENDED` or `PENDING_CLOSURE` are never given a role and are listed in the
`skipped_account_ids` output, so a closed account cannot fail an apply. An empty
`member_account_ids` is a valid no-op: it creates no provider instance and no
module, and every organization account is reported as skipped.

## The management account

The management account is never part of the member set, even when it is ACTIVE and
listed in `member_account_ids`: it has no member access role, and a role created
there would be a different install. It appears in `skipped_account_ids`, and the
`management_account_id` output names it. To cover the management account, install
the standalone role there with the default provider of an apply that runs as that
account:

```
module "management_account_scanner_role" {
  source = "neuralsec-io/neuralsec-integrations/aws//modules/cloud-scanner-role"

  external_id          = var.external_id
  neuralsec_broker_arn = var.neuralsec_broker_arn
}
```

If an earlier version of this root, or your own list, put the management account
in the member set, its state holds `module.member_role["<mgmt>"]`. Taking the account
out of the set would plan to destroy that role, which may be one you made by hand. Keep
the role out of the plan with a `removed` block (OpenTofu path), then apply:

```
removed {
  from = module.member_role["111111111111"]

  lifecycle {
    destroy = false
  }
}
```

Use the management account id in place of `111111111111`. The plain Terraform
generator writes the same block, for `module.member_role_<mgmt>`, when it finds the
management account among the accounts it managed before.

The plain Terraform generator leaves the management account out too. It reads the
management account id from the account ARNs of the list, `--management-account <id>`
sets it explicitly, and a `ManagementAccountId` key in a saved list wins over both.

## OpenTofu path

This path requires OpenTofu 1.9 or newer, the first release with provider
`for_each`; `providers.tofu` sets that version constraint, so an older OpenTofu
stops at `tofu init`. The Terraform path needs Terraform 1.4 or newer and AWS
provider 5.34 or newer; the OpenTofu path still needs OpenTofu 1.9 or newer.
One exception: when the management account was managed before, the generated
file carries a `removed` block for it, which needs Terraform 1.7 or newer.

OpenTofu reads `providers.tofu`, which declares one provider instance per account
with provider `for_each` and one `cloud-scanner-role` module per ACTIVE account.
A provider `for_each` cannot read a data source, so the account list comes in as
`member_account_ids`. Get it with a read-only call:

```
aws organizations list-accounts \
  --query 'Accounts[?State==`ACTIVE` || (State==null && Status==`ACTIVE`)].Id' --output json
```

Leave the management account id out of the list or keep it: the rollout skips it.

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

Terraform has no provider `for_each`, so `gen-org-providers.sh`, which ships in
this module directory, reads the organization with
`aws organizations list-accounts` and writes `providers.generated.tf`: one
aliased provider and one `cloud-scanner-role` module block per ACTIVE account.
The file is not committed (it is in `.gitignore`), because it holds your account
IDs.

From this directory:

```
bash gen-org-providers.sh
terraform init
terraform plan -var 'external_id=neuralsec-...' \
  -var 'neuralsec_broker_arn=arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker'
```

The default output is `providers.generated.tf` next to the script, whatever the
working directory is, so the file lands where the module reads it.

With Terragrunt, write the file next to your `terragrunt.hcl`. Terragrunt copies
that directory into the module's working directory, so the generated
`../../cloud-scanner-role` source resolves:

```
bash .terragrunt-cache/.../org-rollout/gen-org-providers.sh \
  --out "$PWD/providers.generated.tf"
```

If you call org-rollout from your own root module instead, the generated module
blocks must point at `cloud-scanner-role` from your root: replace
`../../cloud-scanner-role` with the published module source.

Options: `--accounts <file>` for a saved `list-accounts` JSON instead of the CLI,
`--out <file>`, `--role-name`, `--partition`, `--exclude <id,id>`,
`--management-account <id>` and `--keep <id,id>`.

The generator keeps a provider block for every account it managed before. The
previous run is read from the existing output file, so an account that is
suspended or closed after its role was created still has a provider, and
Terraform can plan the removal of its module instead of failing on a missing
provider. `--keep` adds ids when the output file is gone. A retained provider is
marked with a `Retained:` comment and has no module. Once the account is closed
for good, stop tracking the role in state, then delete the provider block:

```
removed {
  from = module.member_role_111111111111

  lifecycle {
    destroy = false
  }
}
```

or `terraform state rm module.member_role_111111111111`. Terraform cannot destroy a
role in a closed account, so use one of the two instead of a plain removal.

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
destroyed or its state is removed as described above.
