# OpenTofu path for org-rollout. This test lives next to the root because it
# asserts on the module call declared in providers.tofu, which plain Terraform
# never reads. Run it with `tofu test` from this directory.
#
# The .tofutest.hcl extension keeps plain Terraform from loading a file whose
# assertions cannot exist in its configuration. The same behaviour is covered
# from the repository root by terraform/tests/org_rollout.tofutest.hcl.
#
# The module instances are overridden, so no provider instance ever assumes a
# role and no AWS call is made.

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
      ]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

override_module {
  target = module.member_role
  outputs = {
    role_arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner"
  }
}

variables {
  external_id          = "neuralsec-0123456789abcdef0123456789abcdef"
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-cloud-scanner-broker"
  member_account_ids   = ["111111111111", "222222222222", "333333333333"]
}

run "one_module_instance_per_active_account" {
  command = plan

  assert {
    condition     = length(module.member_role) == 2
    error_message = "Three accounts with one suspended must produce two cloud-scanner-role instances."
  }

  assert {
    condition     = sort(keys(module.member_role)) == tolist(["111111111111", "222222222222"])
    error_message = "The suspended account must not get a module instance."
  }
}

run "suspended_account_is_skipped_without_a_provider_error" {
  command = plan

  assert {
    condition     = output.skipped_account_ids == tolist(["333333333333"])
    error_message = "The suspended account must be listed as skipped."
  }
}
