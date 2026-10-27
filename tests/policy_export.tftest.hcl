# The exported action list must be the real export of the app-api type catalog,
# never the hand written placeholder that shipped before that catalog existed,
# and it must name the catalog revision it came from. Plan only: the policy
# module creates no resources.

run "export_is_the_real_catalog_export" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["s3:ListAllMyBuckets"]
  }

  assert {
    condition     = !can(jsondecode(file("${path.cwd}/modules/policy/actions.json")).placeholder)
    error_message = "actions.json still carries the placeholder marker; replace it with the real catalog export."
  }

  assert {
    condition     = can(regex("^[0-9a-f]{7,40}$", jsondecode(file("${path.cwd}/modules/policy/actions.json")).version))
    error_message = "actions.json version must be the app-api git sha the export was generated from."
  }
}

run "export_sets_are_disjoint_and_organizations_only_in_org_reader" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["s3:ListAllMyBuckets"]
  }

  assert {
    condition     = alltrue([for action in jsondecode(file("${path.cwd}/modules/policy/actions.json")).org_reader : startswith(action, "organizations:")])
    error_message = "org_reader must hold organizations actions only."
  }

  assert {
    condition     = alltrue([for action in jsondecode(file("${path.cwd}/modules/policy/actions.json")).account : !startswith(action, "organizations:")])
    error_message = "Organizations actions belong to the org-reader role, never the member role."
  }

  assert {
    condition = length(setsubtract(
      jsondecode(file("${path.cwd}/modules/policy/actions.json")).account,
      jsondecode(file("${path.cwd}/modules/policy/actions.json")).org_reader
    )) == length(jsondecode(file("${path.cwd}/modules/policy/actions.json")).account)
    error_message = "account and org_reader must not share actions."
  }
}
