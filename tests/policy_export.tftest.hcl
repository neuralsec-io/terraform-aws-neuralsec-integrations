# The action list must be a released list of the Neuralsec scanner's read
# actions, never a placeholder, and it must name the version it came from.
# Plan only: the policy module creates no resources.

run "export_is_a_released_action_list" {
  command = plan

  module {
    source = "./modules/policy"
  }

  variables {
    actions = ["s3:ListAllMyBuckets"]
  }

  assert {
    condition     = !can(jsondecode(file("${path.cwd}/modules/policy/actions.json")).placeholder)
    error_message = "actions.json still carries the placeholder marker; replace it with a released action list."
  }

  assert {
    condition     = can(regex("^[0-9a-f]{7,40}$", jsondecode(file("${path.cwd}/modules/policy/actions.json")).version))
    error_message = "actions.json version must be the Neuralsec revision the export was generated from."
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
    condition     = alltrue([for action in jsondecode(file("${path.cwd}/modules/policy/actions.json")).account : (!startswith(action, "organizations:") || action == "organizations:DescribeOrganization")])
    error_message = "Organizations actions belong to the org-reader role, never the member role, except the dual read organizations:DescribeOrganization."
  }

  assert {
    condition = length(setsubtract(
      setsubtract(jsondecode(file("${path.cwd}/modules/policy/actions.json")).account, ["organizations:DescribeOrganization"]),
      jsondecode(file("${path.cwd}/modules/policy/actions.json")).org_reader
    )) == length(setsubtract(jsondecode(file("${path.cwd}/modules/policy/actions.json")).account, ["organizations:DescribeOrganization"]))
    error_message = "account and org_reader must not share actions, except the dual read organizations:DescribeOrganization."
  }
}
