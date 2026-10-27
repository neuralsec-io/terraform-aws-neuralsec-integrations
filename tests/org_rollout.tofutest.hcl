# org-rollout, OpenTofu path. OpenTofu reads providers.tofu in this module, so the
# root also declares one aliased provider instance per requested account and one
# cloud-scanner-role module per ACTIVE account. This file mocks those provider
# instances and asserts on the module instances and the filter outputs.
#
# OpenTofu loads this file instead of terraform/tests/org_rollout.tftest.hcl, because a
# .tofutest.hcl takes precedence over the .tftest.hcl with the same base name.
# Terraform ignores it and runs the .tftest.hcl variant, which sees no
# providers.tofu. mock_provider for_each is OpenTofu only, which is why the file
# is split.
#
# Everything runs offline: no credentials and no AWS call.

mock_provider "aws" {
  alias    = "member"
  for_each = toset(["111111111111", "222222222222", "333333333333", "444444444444"])

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::111111111111:policy/neuralsec-cloud-scanner-read-01"
      id  = "ANPAEXAMPLEEXAMPLE01"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner"
      id  = "AROAEXAMPLEEXAMPLE01"
    }
  }
}

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

  assert {
    condition     = length(module.member_role) == 2
    error_message = "Two active accounts must produce two cloud-scanner-role instances."
  }

  assert {
    condition     = sort(keys(module.member_role)) == tolist(["111111111111", "222222222222"])
    error_message = "A suspended or pending closure account must not get a module instance."
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

  assert {
    condition     = sort(keys(module.member_role)) == tolist(["111111111111"])
    error_message = "An excluded account must not get a module instance."
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

  assert {
    condition     = length(module.member_role) == 0
    error_message = "Without member_account_ids no cloud-scanner-role instance may be created."
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
