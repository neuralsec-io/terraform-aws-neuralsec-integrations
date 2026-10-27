# codeartifact-read-role module. It reproduces the role app-api renders for an
# aws_codeartifact registry today (registryservice codeArtifactRoleScope): the
# role and its path parsed from the registry role ARN, inline policy
# neuralsec-codeartifact-read, trust on every sibling ExternalId of the shared
# role, and the domain and repository ARNs of every sibling domain. Plan only
# with a mocked AWS provider: no credentials, no API calls.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/neuralsec-registry-read"
      id  = "AROAEXAMPLEEXAMPLE02"
    }
  }
}

variables {
  external_ids = [
    "neuralsec-fedcba9876543210fedcba9876543210",
    "neuralsec-0123456789abcdef0123456789abcdef",
  ]
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"
  domains = [
    { region = "eu-west-1", domain_owner = "111111111111", domain = "pypi" },
    { region = "eu-west-1", domain_owner = "111111111111", domain = "maven" },
    { region = "eu-west-1", domain_owner = "222222222222", domain = "npm" },
  ]
}

run "role_matches_the_app_api_snippet" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  assert {
    condition     = aws_iam_role.this.name == "neuralsec-registry-read"
    error_message = "The default role name must stay neuralsec-registry-read, as app-api renders it."
  }

  assert {
    condition     = aws_iam_role.this.path == "/"
    error_message = "With no role path the IAM path is /, matching the app-api snippet."
  }

  assert {
    condition     = aws_iam_role_policy.this.name == "neuralsec-codeartifact-read"
    error_message = "The inline policy name is part of the app-api contract."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.this.policy).Statement) == 3
    error_message = "The policy must hold exactly the three statements app-api renders."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[0].Action == "codeartifact:GetAuthorizationToken"
    error_message = "Only GetAuthorizationToken belongs on the domain resources."
  }

  assert {
    condition = jsonencode(sort(tolist(jsondecode(aws_iam_role_policy.this.policy).Statement[0].Resource))) == jsonencode([
      "arn:aws:codeartifact:eu-west-1:111111111111:domain/maven",
      "arn:aws:codeartifact:eu-west-1:111111111111:domain/pypi",
      "arn:aws:codeartifact:eu-west-1:222222222222:domain/npm",
    ])
    error_message = "GetAuthorizationToken must be scoped to every sibling domain, sorted."
  }

  assert {
    condition = jsonencode(sort(tolist(jsondecode(aws_iam_role_policy.this.policy).Statement[1].Action))) == jsonencode([
      "codeartifact:GetRepositoryEndpoint",
      "codeartifact:ReadFromRepository",
    ])
    error_message = "The repository actions must be exactly the two read actions app-api grants."
  }

  assert {
    condition = jsonencode(sort(tolist(jsondecode(aws_iam_role_policy.this.policy).Statement[1].Resource))) == jsonencode([
      "arn:aws:codeartifact:eu-west-1:111111111111:repository/maven/*",
      "arn:aws:codeartifact:eu-west-1:111111111111:repository/pypi/*",
      "arn:aws:codeartifact:eu-west-1:222222222222:repository/npm/*",
    ])
    error_message = "The repository actions must be scoped to every sibling domain, sorted."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[2].Action == "sts:GetServiceBearerToken"
    error_message = "Only GetServiceBearerToken belongs on the wildcard resource."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[2].Resource == "*"
    error_message = "Only sts:GetServiceBearerToken may use a wildcard resource."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[2].Condition.StringEquals["sts:AWSServiceName"] == "codeartifact.amazonaws.com"
    error_message = "GetServiceBearerToken must be limited to the CodeArtifact service."
  }

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : [
        for a in try(tolist(s.Action), [tostring(s.Action)]) : !strcontains(a, "*")
      ]
    ]))
    error_message = "No policy statement may use an action wildcard."
  }
}

run "trust_covers_every_sibling_external_id" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "The trust policy holds one statement, as app-api renders it."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.AWS == var.neuralsec_broker_arn
    error_message = "The role must trust only the Neuralsec broker."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "The trust statement must grant only sts:AssumeRole."
  }

  assert {
    condition     = jsonencode(sort(tolist(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"]))) == jsonencode(sort(var.external_ids))
    error_message = "The trust policy must require one sts:ExternalId condition per sibling ExternalId, sorted."
  }
}

run "custom_role_name_and_path_follow_the_registry_arn" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    role_name = "custom-reader"
    role_path = "/team/sub/"
  }

  assert {
    condition     = aws_iam_role.this.name == "custom-reader"
    error_message = "A registry role ARN with a custom name must be reproduced faithfully."
  }

  assert {
    condition     = aws_iam_role.this.path == "/team/sub/"
    error_message = "A registry role ARN with a path must be reproduced faithfully."
  }
}

run "rejects_a_malformed_external_id" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    external_ids = ["neuralsec-not-a-hex-id"]
  }

  expect_failures = [var.external_ids]
}

run "rejects_an_empty_external_id_list" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    external_ids = []
  }

  expect_failures = [var.external_ids]
}

run "rejects_a_malformed_broker_arn" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    neuralsec_broker_arn = "neuralsec-broker"
  }

  expect_failures = [var.neuralsec_broker_arn]
}

run "rejects_a_malformed_domain_owner" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    domains = [{ region = "eu-west-1", domain_owner = "12345", domain = "maven" }]
  }

  expect_failures = [var.domains]
}

run "rejects_a_malformed_domain_name" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    domains = [{ region = "eu-west-1", domain_owner = "111111111111", domain = "Maven Domain" }]
  }

  expect_failures = [var.domains]
}

run "rejects_an_empty_domain_list" {
  command = plan

  module {
    source = "./modules/codeartifact-read-role"
  }

  variables {
    domains = []
  }

  expect_failures = [var.domains]
}
