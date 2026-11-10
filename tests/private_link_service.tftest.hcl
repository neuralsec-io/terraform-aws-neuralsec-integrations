# private-link-service module. Plan only with mocked AWS and time providers: no
# credentials, no API calls. It covers the one-target-set rule, the role ARN
# validation, the cross-region supported_regions list, the bring-your-own
# load balancer path, the single allowed principal and the release tags.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "eu-west-1"
      region = "eu-west-1"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/neuralsec-pl-registry/0123456789abcdef"
      id  = "net/neuralsec-pl-registry/0123456789abcdef"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:targetgroup/neuralsec-pl-registry/0123456789abcdef"
      id  = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:targetgroup/neuralsec-pl-registry/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:listener/net/neuralsec-pl-registry/0123456789abcdef/0123456789abcdef"
    }
  }

  mock_resource "aws_vpc_endpoint_service" {
    defaults = {
      id           = "vpce-svc-0123456789abcdef0"
      service_name = "com.amazonaws.vpce.eu-west-1.vpce-svc-0123456789abcdef0"
    }
  }
}

mock_provider "time" {
  mock_resource "time_static" {
    defaults = {
      rfc3339 = "2026-11-10T00:00:00Z"
    }
  }
}

variables {
  name                    = "registry"
  neuralsec_org_id        = "00000000-0000-4000-8000-000000000000"
  neuralsec_org_slug      = "example"
  neuralsec_principal_arn = "arn:aws:iam::111111111111:role/neuralsec-app"
  neuralsec_region        = "eu-west-1"
  vpc_id                  = "vpc-0123456789abcdef0"
  subnet_ids = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
  ]
  target_ips = ["10.0.1.10", "10.0.2.10"]
}

run "ip_targets_publish_the_service" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition     = length(aws_lb.this) == 1 && aws_lb.this[0].internal && aws_lb.this[0].load_balancer_type == "network"
    error_message = "An internal network load balancer is created by default."
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "ip"
    error_message = "target_ips must produce an ip target group."
  }

  assert {
    condition     = aws_lb_target_group.this[0].port == 443
    error_message = "The target group uses the target port, 443 by default."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.this) == 2
    error_message = "One target group attachment per target IP."
  }

  assert {
    condition     = aws_lb_listener.this[0].port == 443 && aws_lb_listener.this[0].protocol == "TCP"
    error_message = "The listener stays on TCP 443: Neuralsec speaks HTTPS only."
  }

  assert {
    condition     = toset([for rule in aws_security_group.this[0].egress : rule.cidr_blocks[0]]) == toset([for address in var.target_ips : "${address}/32"])
    error_message = "The load balancer security group egress is scoped to the target IPs."
  }

  assert {
    condition     = aws_vpc_endpoint_service.this.allowed_principals == toset([var.neuralsec_principal_arn])
    error_message = "The endpoint service allows exactly the Neuralsec principal."
  }

  assert {
    condition     = aws_vpc_endpoint_service.this.acceptance_required == false
    error_message = "Acceptance is automatic by default."
  }
}

run "instance_targets_use_the_vpc_cidr" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips          = []
    target_instance_ids = ["i-0123456789abcdef0"]
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "instance"
    error_message = "target_instance_ids must produce an instance target group."
  }

  assert {
    condition     = toset([for rule in aws_security_group.this[0].egress : rule.cidr_blocks[0]]) == toset(["10.0.0.0/16"])
    error_message = "Instance targets can move within the VPC, so the egress rule covers the VPC CIDR."
  }
}

run "rejects_both_target_sets" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_instance_ids = ["i-0123456789abcdef0"]
  }

  expect_failures = [aws_vpc_endpoint_service.this]
}

run "rejects_no_target_set" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips = []
  }

  expect_failures = [aws_vpc_endpoint_service.this]
}

run "byo_nlb_skips_the_load_balancer" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips       = []
    existing_nlb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  assert {
    condition     = length(aws_lb.this) == 0 && length(aws_security_group.this) == 0
    error_message = "A supplied load balancer skips the load balancer and its security group."
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener.this) == 0
    error_message = "A supplied load balancer skips the target group and the listener."
  }

  assert {
    condition     = aws_vpc_endpoint_service.this.network_load_balancer_arns == toset([var.existing_nlb_arn])
    error_message = "The endpoint service publishes the supplied load balancer."
  }

  assert {
    condition     = output.nlb_arn == var.existing_nlb_arn && output.nlb_security_group_id == null
    error_message = "The outputs describe the supplied load balancer and no security group."
  }
}

run "cross_region_adds_both_regions" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    neuralsec_region = "us-east-1"
  }

  assert {
    condition = (
      length(aws_vpc_endpoint_service.this.supported_regions) == 2 &&
      toset(aws_vpc_endpoint_service.this.supported_regions) == toset(["eu-west-1", "us-east-1"])
    )
    error_message = "A Neuralsec region other than the stack region must be enabled next to the stack region, which AWS always reports as supported."
  }
}

run "rejects_a_name_that_ends_in_a_hyphen" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    name = "abc-"
  }

  expect_failures = [var.name]
}

run "rejects_a_name_over_19_characters" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    name = "abcdefghijklmnopqrst"
  }

  expect_failures = [var.name]
}

run "accepts_a_single_character_name" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    name = "a"
  }

  assert {
    condition     = aws_lb.this[0].name == "neuralsec-pl-a"
    error_message = "A single letter or digit is a valid name."
  }
}

run "accepts_a_hyphen_inside_the_name" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    name = "ab-c"
  }

  assert {
    condition     = aws_lb.this[0].name == "neuralsec-pl-ab-c"
    error_message = "Hyphens inside the name are valid."
  }
}

run "accepts_the_longest_name" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    # Exactly 19 characters: the limit that keeps the resource name at 32.
    name = "abcdefghijklmnopqrs"
  }

  assert {
    condition     = aws_lb.this[0].name == "neuralsec-pl-abcdefghijklmnopqrs"
    error_message = "A 19 character name still fits the 32 character load balancer name limit."
  }
}

run "rejects_a_malformed_principal_arn" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    neuralsec_principal_arn = "neuralsec-app"
  }

  expect_failures = [var.neuralsec_principal_arn]
}

run "rejects_a_malformed_org_id" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    neuralsec_org_id = "not-a-uuid"
  }

  expect_failures = [var.neuralsec_org_id]
}

# The tag contract: every taggable resource says which customer it belongs to
# and when it was created.
run "every_taggable_resource_has_the_five_neuralsec_tags" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition = alltrue([
      for resource_tags in [
        aws_lb.this[0].tags,
        aws_security_group.this[0].tags,
        aws_lb_target_group.this[0].tags,
        aws_lb_listener.this[0].tags,
        aws_vpc_endpoint_service.this.tags,
        ] : alltrue([
          for key in [
            "neuralsec:component",
            "neuralsec:integration-version",
            "neuralsec:org_id",
            "neuralsec:org_slug",
            "neuralsec:created_at",
          ] : contains(keys(resource_tags), key)
      ])
    ])
    error_message = "Every taggable resource must carry the five neuralsec tags."
  }

  assert {
    condition     = aws_lb.this[0].tags["neuralsec:component"] == "private-link-service"
    error_message = "The component tag names this module."
  }

  assert {
    condition     = aws_lb.this[0].tags["neuralsec:org_id"] == var.neuralsec_org_id && aws_lb.this[0].tags["neuralsec:org_slug"] == var.neuralsec_org_slug
    error_message = "The org tags name the customer."
  }

  assert {
    condition     = aws_lb.this[0].tags["Name"] == var.name
    error_message = "The Name tag is the link name."
  }
}

# The template must agree with the module on the contract the customer cannot
# see in a plan: the single principal, the acceptance switch and the
# cross-region list.
run "template_agrees_with_the_module" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition     = length(regexall("AllowedPrincipals:", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1
    error_message = "The template must declare the endpoint service allowed principals."
  }

  assert {
    condition     = length(regexall("- !Ref NeuralsecPrincipalArn", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1
    error_message = "The template allows exactly the NeuralsecPrincipalArn parameter."
  }

  assert {
    condition     = length(regexall("AcceptanceRequired", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) > 0
    error_message = "The template must expose the acceptance switch."
  }

  assert {
    condition     = length(regexall("!Ref \"AWS::Region\", !Ref NeuralsecRegion", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1
    error_message = "The template must list the stack region next to the Neuralsec region, as the module does."
  }

  assert {
    condition     = length(regexall("SupportedRegions", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) > 0
    error_message = "The template must enable the Neuralsec region when it differs."
  }
}
