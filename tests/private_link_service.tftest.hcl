# private-link-service module. Run with mocked AWS and time providers: no
# credentials, no API calls. It covers the one-target-set rule, the ignored
# targets on the existing load balancer path, the ALB target group and its
# health check, the generated target group name across a target kind change,
# the role ARN validation, the eu-west-1 Neuralsec region default, the
# cross-region supported_regions list, the bring-your-own load balancer path,
# the single allowed principal and the release tags.

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
    condition     = length(aws_lb_listener.http) == 0 && length(aws_lb_target_group.http) == 0 && length(aws_lb_target_group_attachment.http) == 0
    error_message = "Plain HTTP is off by default: no port 80 listener, target group or attachment."
  }

  assert {
    condition     = aws_lb_listener.this[0].port == 443 && aws_lb_listener.this[0].protocol == "TCP"
    error_message = "The 443 listener stays on TCP and is HTTPS; port 80 is an optional plain HTTP listener, off by default."
  }

  assert {
    condition     = length(aws_lb_listener.this[0].default_action) == 1 && aws_lb_listener.this[0].default_action[0].type == "forward"
    error_message = "The listener forwards to the target group this module creates."
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

run "http_target_port_adds_a_port_80_listener" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    http_target_port = 8080
  }

  assert {
    condition     = aws_lb_listener.http[0].port == 80 && aws_lb_listener.http[0].protocol == "TCP"
    error_message = "http_target_port adds a TCP 80 listener."
  }

  assert {
    condition     = aws_lb_listener.this[0].port == 443 && aws_lb_target_group.this[0].port == 443
    error_message = "The 443 listener and its target group are unchanged."
  }

  assert {
    condition     = aws_lb_target_group.http[0].port == 8080 && aws_lb_target_group.http[0].target_type == "ip"
    error_message = "The HTTP target group uses http_target_port and the same target kind."
  }

  assert {
    condition     = aws_lb_target_group.http[0].health_check[0].protocol == "TCP" && aws_lb_target_group.http[0].health_check[0].port == "8080"
    error_message = "The HTTP target group uses a TCP health check on its port."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.http) == 2 && alltrue([for a in aws_lb_target_group_attachment.http : a.port == 8080])
    error_message = "The HTTP target group registers the same targets as the 443 path, on http_target_port."
  }

  assert {
    condition     = keys(aws_lb_listener.http[0].tags) == keys(aws_lb_listener.this[0].tags) && keys(aws_lb_target_group.http[0].tags) == keys(aws_lb_target_group.this[0].tags)
    error_message = "The HTTP resources carry the same tags."
  }

  assert {
    condition     = contains([for rule in aws_security_group.this[0].egress : rule.from_port], 8080) && contains([for rule in aws_security_group.this[0].egress : rule.from_port], 443)
    error_message = "The security group also allows egress on http_target_port, next to the target port."
  }
}

run "http_target_port_equal_to_target_port_adds_no_duplicate_rule" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    http_target_port = 443
  }

  assert {
    condition     = length(aws_security_group.this[0].egress) == 2
    error_message = "One egress rule per target IP even when both ports match."
  }
}

run "http_target_port_with_an_alb_target_uses_an_http_health_check" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips       = []
    target_alb_arn   = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
    http_target_port = 80
  }

  assert {
    condition     = aws_lb_target_group.http[0].target_type == "alb" && aws_lb_target_group.http[0].health_check[0].protocol == "HTTP"
    error_message = "An alb target group needs an HTTP health check."
  }
}

run "http_target_port_is_ignored_with_an_existing_nlb" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips       = []
    http_target_port = 8080
    existing_nlb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  assert {
    condition     = length(aws_lb_listener.http) == 0 && length(aws_lb_target_group.http) == 0
    error_message = "With an existing load balancer the customer adds the port 80 listener themselves."
  }
}

run "rejects_an_http_target_port_out_of_range" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    http_target_port = 70000
  }

  expect_failures = [var.http_target_port]
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

run "alb_target_uses_an_alb_target_group" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips     = []
    target_alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "alb"
    error_message = "target_alb_arn must produce an alb target group."
  }

  assert {
    condition     = aws_lb_target_group.this[0].port == 443 && aws_lb_target_group.this[0].protocol == "TCP"
    error_message = "The ALB target group forwards TCP to the ALB listener port."
  }

  assert {
    condition = (
      length(aws_lb_target_group_attachment.this) == 1 &&
      aws_lb_target_group_attachment.this[0].target_id == var.target_alb_arn &&
      aws_lb_target_group_attachment.this[0].port == 443
    )
    error_message = "The ALB is the single attachment, on the target port."
  }

  assert {
    condition = (
      aws_lb_target_group.this[0].health_check[0].protocol == "HTTPS" &&
      aws_lb_target_group.this[0].health_check[0].port == tostring(var.target_port) &&
      aws_lb_target_group.this[0].health_check[0].path == "/" &&
      aws_lb_target_group.this[0].health_check[0].matcher == "200-499"
    )
    error_message = "An alb target group needs an HTTPS health check on the ALB listener port: any answer means the ALB is up."
  }

  assert {
    condition     = toset([for rule in aws_security_group.this[0].egress : rule.cidr_blocks[0]]) == toset(["10.0.0.0/16"])
    error_message = "The ALB addresses move within the VPC, so the egress rule covers the VPC CIDR."
  }

  assert {
    condition     = aws_lb_listener.this[0].port == 443 && length(aws_vpc_endpoint_service.this.network_load_balancer_arns) == 1
    error_message = "The private link still publishes the created network load balancer."
  }
}

# Changing the target kind replaces the target group. Its name is unique per
# apply: a generated suffix keeps the old group and the new one apart while
# both exist, and the Name tag still carries the link name.
run "target_group_name_is_generated_so_a_kind_change_does_not_fail" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition     = aws_lb_target_group.this[0].name_prefix == "nspl-"
    error_message = "The target group name must be generated, so a replacement can create the new group next to the old one."
  }

  assert {
    condition     = aws_lb_target_group.this[0].tags["Name"] == var.name
    error_message = "The generated name must still carry the link name in the Name tag."
  }
}

run "rejects_alb_with_ip_targets" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
  }

  expect_failures = [aws_vpc_endpoint_service.this]
}

run "rejects_alb_with_existing_nlb" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips       = []
    target_alb_arn   = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
    existing_nlb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  expect_failures = [aws_vpc_endpoint_service.this]
}

run "rejects_alb_with_instance_targets" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips          = []
    target_alb_arn      = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
    target_instance_ids = ["i-0123456789abcdef0"]
  }

  expect_failures = [aws_vpc_endpoint_service.this]
}

run "rejects_a_network_load_balancer_arn_as_the_alb" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips     = []
    target_alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  expect_failures = [var.target_alb_arn]
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

# An existing load balancer publishes the service as it is. The target inputs
# are only used to build the load balancer, target group and listener this
# module creates, so alongside existing_nlb_arn they change nothing: a caller
# that set them before the existing NLB path keeps the same plan. Only
# target_alb_arn is rejected next to it, because an ALB target is the one kind
# that would otherwise look applied while the existing load balancer forwards
# to its own targets.
run "existing_nlb_with_ips_still_plans" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    existing_nlb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  assert {
    condition     = length(aws_lb.this) == 0 && length(aws_lb_target_group.this) == 0 && length(aws_lb_target_group_attachment.this) == 0
    error_message = "With an existing load balancer, the target IPs are ignored and no load balancer, target group or attachment is created."
  }

  assert {
    condition     = aws_vpc_endpoint_service.this.network_load_balancer_arns == toset([var.existing_nlb_arn])
    error_message = "The endpoint service publishes the existing load balancer, whatever target_ips holds."
  }
}

run "existing_nlb_with_instance_ids_still_plans" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips          = []
    target_instance_ids = ["i-0123456789abcdef0"]
    existing_nlb_arn    = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/net/existing/0123456789abcdef"
  }

  assert {
    condition     = length(aws_lb.this) == 0 && length(aws_security_group.this) == 0 && length(aws_lb_target_group.this) == 0
    error_message = "With an existing load balancer, the target instance ids are ignored and no target resources are created."
  }

  assert {
    condition     = aws_vpc_endpoint_service.this.network_load_balancer_arns == toset([var.existing_nlb_arn])
    error_message = "The endpoint service publishes the existing load balancer, whatever target_instance_ids holds."
  }
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
    condition     = output.nlb_arn == var.existing_nlb_arn && output.nlb_security_group_id == null && output.load_balancer_security_group_id == null
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

# Neuralsec runs in eu-west-1, which is now the default, so a customer plan
# leaves the input out. An apply must succeed and behave exactly as passing
# eu-west-1 by hand did: this suite's stack region is eu-west-1, so the endpoint
# service is not asked for a cross-region list and adds none.
run "default_region_is_eu_west_1" {
  command = apply

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition     = var.neuralsec_region == "eu-west-1"
    error_message = "neuralsec_region must default to eu-west-1, the region Neuralsec runs in."
  }

  assert {
    condition     = local.cross_region == false
    error_message = "With the default equal to the stack region, supported_regions stays unset, as it did when eu-west-1 was passed by hand."
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

  assert {
    condition     = length(regexall("Leave TargetAlbArn empty when ExistingNlbArn is set", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1
    error_message = "The template rejects only an ALB target next to ExistingNlbArn, as the module does; targets on an existing load balancer are ignored."
  }
}

run "template_has_the_optional_http_listener" {
  command = plan

  module {
    source = "./modules/private-link-service"
  }

  assert {
    condition     = length(regexall("HttpTargetPort:", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1 && length(regexall("Port: 80\n", file("${path.cwd}/../cloudformation/templates/private-link-service.yaml"))) == 1
    error_message = "The template exposes HttpTargetPort and one port 80 listener."
  }
}

# Changing the target kind on a live link replaces the target group. The runs
# below apply one kind after another on one state: each must apply, and the
# listener must forward to the new group in the same apply. The generated name
# is what lets AWS hold the old group and the new one at once; with a fixed name
# the second create would be rejected.
run "target_kind_change_to_alb_applies" {
  command = apply

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips     = []
    target_alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "alb" && length(aws_lb_target_group_attachment.this) == 1
    error_message = "A link that published IP targets applies again with an ALB target."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].target_group_arn == aws_lb_target_group.this[0].arn
    error_message = "The listener forwards to the new target group in the same apply, so the link keeps serving traffic."
  }
}

run "target_kind_change_to_instances_applies" {
  command = apply

  module {
    source = "./modules/private-link-service"
  }

  variables {
    target_ips          = []
    target_instance_ids = ["i-0123456789abcdef0"]
  }

  assert {
    condition     = aws_lb_target_group.this[0].target_type == "instance" && length(aws_lb_target_group_attachment.this) == 1
    error_message = "The same link applies again with an instance target."
  }

  assert {
    condition     = aws_lb_listener.this[0].default_action[0].target_group_arn == aws_lb_target_group.this[0].arn
    error_message = "The listener follows the target group through a second kind change."
  }
}
