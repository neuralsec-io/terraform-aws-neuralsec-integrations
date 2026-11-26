#!/usr/bin/env bash
# Writes providers.generated.tf next to this script, in the org-rollout module
# directory, for the plain Terraform path.
#
# The ACTIVE filter reads the account `State` and falls back to the deprecated
# `Status` when a record has no State. The management account is never a member:
# its member access role does not exist, so it is left out (cover it with a
# standalone cloud-scanner-role module and the default provider). An account that
# was managed before and is no longer ACTIVE keeps its provider block, read from
# the existing output file or --keep, so Terraform can still plan its removal. A
# previously managed management account also gets a removed block with
# lifecycle { destroy = false }, so its role is never destroyed.
#
# OpenTofu does not need this file: it reads providers.tofu from this same
# directory, which uses provider for_each. Terraform has no provider for_each,
# so this script turns the organization account list into static aliased
# providers and one cloud-scanner-role module block per ACTIVE account. The
# module blocks source "../../cloud-scanner-role", which resolves from here.
#
# The account list is read with `aws organizations list-accounts`, a read action,
# or from a JSON file in the same shape ({"Accounts": [...]}) for tests and for
# accounts that cannot run the CLI.
#
# Usage:
#   bash gen-org-providers.sh [options]
#
# Run it from this directory, the org-rollout module. When the module is
# consumed remotely (Terragrunt, or a git source that fetches the published
# module), a relative default would land inside the fetched package: pass
# --out <your root dir>/providers.generated.tf instead.
#
# Options:
#   -a, --accounts <file>      JSON account list instead of calling the AWS CLI.
#   -o, --out <file>           Output path. Default providers.generated.tf in the
#                              directory of this script.
#   -r, --role-name <name>     Member access role name. Default OrganizationAccountAccessRole.
#   -p, --partition <name>     ARN partition. Default aws.
#   -x, --exclude <id,id>      Account IDs to leave out even when ACTIVE.
#   -m, --management-account <id>
#                              Management account ID to leave out. Default: the account
#                              in the ARNs of the list ({"ManagementAccountId": ...} wins).
#   -k, --keep <id,id>         Previously managed account IDs that keep a provider block
#                              even when no longer ACTIVE. The IDs already in the output
#                              file are kept too.
#   -h, --help                 Print this help.
#
# Requires jq.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

accounts_file=""
out_file="${script_dir}/providers.generated.tf"
role_name="OrganizationAccountAccessRole"
partition="aws"
exclude_csv=""
management_id=""
keep_csv=""

usage() {
  sed -n '2,/^# Requires jq\.$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a | --accounts)
      accounts_file="$2"
      shift 2
      ;;
    -o | --out)
      out_file="$2"
      shift 2
      ;;
    -r | --role-name)
      role_name="$2"
      shift 2
      ;;
    -p | --partition)
      partition="$2"
      shift 2
      ;;
    -x | --exclude)
      exclude_csv="$2"
      shift 2
      ;;
    -m | --management-account)
      management_id="$2"
      shift 2
      ;;
    -k | --keep)
      keep_csv="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "gen-org-providers: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "gen-org-providers: jq is required" >&2
  exit 2
fi

if [ -z "${accounts_file}" ]; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "gen-org-providers: pass --accounts <file> or install the AWS CLI" >&2
    exit 2
  fi
  accounts_json="$(aws organizations list-accounts --output json)"
else
  if [ ! -r "${accounts_file}" ]; then
    echo "gen-org-providers: cannot read ${accounts_file}" >&2
    exit 2
  fi
  accounts_json="$(cat "${accounts_file}")"
fi

# Accept {"Accounts": [...]} (the CLI shape) or a bare array.
if ! printf '%s' "${accounts_json}" | jq -e 'if type == "object" then (.Accounts | type == "array") else (. | type == "array") end' >/dev/null; then
  echo "gen-org-providers: account list must be {\"Accounts\": [...]} or [...]" >&2
  exit 1
fi

# The management account is the account id inside every account ARN of the list.
if [ -z "${management_id}" ]; then
  management_id="$(
    printf '%s' "${accounts_json}" | jq -r '
      if type == "object" and (.ManagementAccountId // "") != "" then .ManagementAccountId
      else (if type == "object" then .Accounts else . end)
        | map(.Arn // empty | capture("^arn:[^:]+:organizations::(?<id>[0-9]{12}):account/") | .id)
        | first // "" end'
  )"
fi

if ! printf '%s' "${management_id}" | grep -Eq '^([0-9]{12})?$'; then
  echo "gen-org-providers: management account must be a 12 digit account ID" >&2
  exit 2
fi

# Active member accounts: State, else the deprecated Status, is ACTIVE; the
# management account and the excluded accounts are left out.
account_ids="$(
  printf '%s' "${accounts_json}" | jq -r --arg exclude "${exclude_csv}" --arg management "${management_id}" '
    (if type == "object" then .Accounts else . end)
    | map(select((.State // .Status) == "ACTIVE"))
    | map(.Id)
    | map(select(. != $management))
    | map(select(. as $id | ($exclude | split(",") | map(select(length > 0))) | index($id) | not))
    | sort
    | .[]'
)"

# Previously managed accounts that are no longer active members keep a provider
# block: Terraform needs the provider to plan the removal of their module.
previous_ids="$(
  {
    if [ -r "${out_file}" ]; then
      sed -n 's/^  alias = "member_\([0-9]\{12\}\)"$/\1/p' "${out_file}"
    fi
    printf '%s\n' "${keep_csv}" | tr ',' '\n'
  } | grep -E '^[0-9]{12}$' | sort -u || true
)"

retained_ids=""
for previous_id in ${previous_ids}; do
  if ! printf '%s\n' "${account_ids}" | grep -qx "${previous_id}"; then
    retained_ids="${retained_ids}${previous_id}"$'\n'
  fi
done
retained_ids="$(printf '%s' "${retained_ids}" | sed '/^$/d')"

tmp_file="$(mktemp "${out_file}.XXXXXX")"

{
  echo "// Generated by gen-org-providers.sh. Do not edit."
  echo "// Plain Terraform path for org-rollout: OpenTofu uses providers.tofu instead."
  echo "// Delete this file before running OpenTofu."
  echo
  echo "// Active accounts: $(printf '%s' "${account_ids}" | grep -c . || true)"
  echo "// Management account left out: ${management_id:-unknown}"
  echo

  for account_id in ${account_ids}; do
    cat <<EOF
provider "aws" {
  alias = "member_${account_id}"

  assume_role {
    role_arn     = "arn:${partition}:iam::${account_id}:role/${role_name}"
    session_name = "neuralsec-cloud-scanner-rollout"
  }
}

module "member_role_${account_id}" {
  source    = "../../cloud-scanner-role"
  providers = { aws = aws.member_${account_id} }

  external_id          = var.external_id
  neuralsec_broker_arn = var.neuralsec_broker_arn
  state_locations      = var.state_locations
}

EOF
  done

  for account_id in ${retained_ids}; do
    if [ "${account_id}" = "${management_id}" ]; then
      # The management account has no member access role and is never a member.
      # A role there from an earlier rollout may be hand made: forget it in
      # state instead of planning its destroy.
      cat <<EOF
// Management account ${account_id}: it was listed as a member before and is
// never one now. The removed block forgets its state without destroying the role.
removed {
  from = module.member_role_${account_id}

  lifecycle {
    destroy = false
  }
}

EOF
    fi
    cat <<EOF
// Retained: ${account_id} was managed before and is not an ACTIVE member now. The
// provider stays so Terraform can plan the removal of module.member_role_${account_id}.
// Remove that module state with a removed block (lifecycle { destroy = false }) or
// terraform state rm, then delete this provider block.
provider "aws" {
  alias = "member_${account_id}"

  assume_role {
    role_arn     = "arn:${partition}:iam::${account_id}:role/${role_name}"
    session_name = "neuralsec-cloud-scanner-rollout"
  }
}

EOF
  done

  echo 'output "member_role_arns" {'
  echo '  description = "Scanner role ARN per member account."'
  if [ -z "${account_ids}" ]; then
    echo '  value = {}'
  else
    echo '  value = {'
    for account_id in ${account_ids}; do
      echo "    \"${account_id}\" = module.member_role_${account_id}.role_arn"
    done
    echo '  }'
  fi
  echo '}'
} >"${tmp_file}"

mv "${tmp_file}" "${out_file}"

echo "gen-org-providers: wrote ${out_file} with $(printf '%s' "${account_ids}" | grep -c . || true) member account(s), $(printf '%s' "${retained_ids}" | grep -c . || true) retained provider(s)"
