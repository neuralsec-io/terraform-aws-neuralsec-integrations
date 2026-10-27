# org-rollout, plain Terraform path. Suspended and excluded accounts must be
# dropped by a filter, never by a provider error. The Terraform path takes its
# account list from scripts/gen-org-providers.sh, so these runs pass
# member_account_ids the way the OpenTofu path does.
#
# Terraform never reads providers.tofu, so these runs see no cloud-scanner-role module
# and need no mock for the per-account provider instances. OpenTofu reads
# providers.tofu and does create those instances; its version of this file is
# terraform/tests/org_rollout.tofutest.hcl. OpenTofu prefers a .tofutest.hcl over the
# .tftest.hcl with the same base name, Terraform ignores .tofutest.hcl, so each
# engine runs the variant that matches the configuration it loads.

mock_provider "aws" {
  mock_data "aws_organizations_organization" {
    defaults = {
      id  = "o-synthetic01"
      arn = "arn:aws:organizations::111111111111:organization/o-synthetic01"
      accounts = [
        {
          id               = "111111111111"
          arn              = "arn:aws:organizations::111111111111:account/o-synthetic01/111111111111"
          email            = "one@example.com"
          name             = "synthetic-one"
          state            = "ACTIVE"
          status           = "ACTIVE"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-02T03:04:05Z"
        },
        {
          id               = "222222222222"
          arn              = "arn:aws:organizations::111111111111:account/o-synthetic01/222222222222"
          email            = "two@example.com"
          name             = "synthetic-two"
          state            = "ACTIVE"
          status           = "ACTIVE"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-02T03:04:05Z"
        },
        {
          id               = "333333333333"
          arn              = "arn:aws:organizations::111111111111:account/o-synthetic01/333333333333"
          email            = "three@example.com"
          name             = "synthetic-three"
          state            = "SUSPENDED"
          status           = "SUSPENDED"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-02T03:04:05Z"
        },
        {
          id               = "444444444444"
          arn              = "arn:aws:organizations::111111111111:account/o-synthetic01/444444444444"
          email            = "four@example.com"
          name             = "synthetic-four"
          state            = "PENDING_CLOSURE"
          status           = "PENDING_CLOSURE"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-02T03:04:05Z"
        },
      ]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker"
}

run "skips_suspended_and_pending_accounts" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org/org-rollout"
  }

  variables {
    member_account_ids = ["111111111111", "222222222222", "333333333333", "444444444444"]
  }

  assert {
    condition     = output.member_account_ids == tolist(["111111111111", "222222222222"])
    error_message = "Only ACTIVE accounts may get the scanner role."
  }

  assert {
    condition     = output.skipped_account_ids == tolist(["333333333333", "444444444444"])
    error_message = "Suspended and pending closure accounts must be reported as skipped, not touched."
  }
}

run "excludes_requested_accounts" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org/org-rollout"
  }

  variables {
    member_account_ids  = ["111111111111", "222222222222", "333333333333", "444444444444"]
    exclude_account_ids = ["222222222222"]
  }

  assert {
    condition     = output.member_account_ids == tolist(["111111111111"])
    error_message = "exclude_account_ids must drop the account from the rollout."
  }

  assert {
    condition     = output.skipped_account_ids == tolist(["222222222222", "333333333333", "444444444444"])
    error_message = "Excluded accounts must be reported as skipped."
  }
}

run "no_accounts_selected_rolls_out_nothing" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org/org-rollout"
  }

  assert {
    condition     = length(output.member_account_ids) == 0
    error_message = "Without member_account_ids the rollout must do nothing."
  }

  assert {
    condition     = output.skipped_account_ids == tolist(["111111111111", "222222222222", "333333333333", "444444444444"])
    error_message = "Every organization account must be reported as skipped when none is requested."
  }
}

run "rejects_a_malformed_external_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org/org-rollout"
  }

  variables {
    external_id = "neuralsec-"
  }

  expect_failures = [var.external_id]
}

run "rejects_a_malformed_exclude_account_id" {
  command = plan

  module {
    source = "./modules/cloud-scanner-org/org-rollout"
  }

  variables {
    exclude_account_ids = ["not-an-account-id"]
  }

  expect_failures = [var.exclude_account_ids]
}
