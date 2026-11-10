locals {
  # The release this module ships in. Bump it with the release tag: every
  # resource carries it as neuralsec:integration-version, and Neuralsec flags a
  # link whose value is older than the current release.
  integration_version = "0.3.0"

  # One place for the release tags, merged into every taggable resource below.
  # A test fails when one of them lacks a key.
  tags = merge(
    {
      "neuralsec:component"           = "private-link-service"
      "neuralsec:integration-version" = local.integration_version
      "neuralsec:org_id"              = var.neuralsec_org_id
      "neuralsec:org_slug"            = var.neuralsec_org_slug
      "neuralsec:created_at"          = time_static.this.rfc3339
      "Name"                          = var.name
    },
    var.tags,
  )

  # The resource name stays within the 32 characters a load balancer and a
  # target group name allow.
  resource_name = "neuralsec-pl-${var.name}"

  create_nlb = var.existing_nlb_arn == null

  target_type = length(var.target_instance_ids) > 0 ? "instance" : "ip"

  # One attachment per target, of exactly one kind: the variable validation
  # rejects a plan that sets both or neither.
  targets = local.create_nlb ? (
    length(var.target_instance_ids) > 0 ? var.target_instance_ids : var.target_ips
  ) : []

  # The load balancer accepts connections only on 443, so its egress is scoped
  # to the targets on the target port. Instance targets can move within the VPC,
  # so their rule covers the VPC CIDR.
  egress_cidrs = local.create_nlb ? (
    length(var.target_instance_ids) > 0 ? [data.aws_vpc.this[0].cidr_block] : [
      for address in var.target_ips : "${address}/32"
    ]
  ) : []

  # PrivateLink traffic comes from the Neuralsec endpoint network interfaces,
  # not from an address the customer can name, so the module turns the inbound
  # rule enforcement off and needs no ingress rule.
  cross_region = var.neuralsec_region != data.aws_region.current.name

  # A supplied load balancer wins; otherwise the one this module creates.
  nlb_arn = one(concat(
    [for load_balancer in aws_lb.this : load_balancer.arn],
    var.existing_nlb_arn == null ? [] : [var.existing_nlb_arn],
  ))
}

data "aws_region" "current" {}

# Only instance targets need the VPC CIDR; IP targets and a supplied load
# balancer need no VPC read at all.
data "aws_vpc" "this" {
  count = local.create_nlb && length(var.target_instance_ids) > 0 ? 1 : 0

  id = var.vpc_id
}

# Fixed at the first apply, so the created_at tag never drifts. A recreate keeps
# the value because the resource is not replaced.
resource "time_static" "this" {}

resource "aws_lb" "this" {
  count = local.create_nlb ? 1 : 0

  name                                                         = local.resource_name
  internal                                                     = true
  load_balancer_type                                           = "network"
  subnets                                                      = var.subnet_ids
  security_groups                                              = [aws_security_group.this[0].id]
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"

  tags = local.tags
}

resource "aws_security_group" "this" {
  count = local.create_nlb ? 1 : 0

  name        = local.resource_name
  description = "Neuralsec private link load balancer"
  vpc_id      = var.vpc_id

  dynamic "egress" {
    for_each = local.create_nlb ? toset(local.egress_cidrs) : toset([])

    content {
      from_port   = var.target_port
      to_port     = var.target_port
      protocol    = "tcp"
      cidr_blocks = [egress.value]
      description = "Neuralsec private link to the service on the target port"
    }
  }

  tags = local.tags
}

resource "aws_lb_target_group" "this" {
  count = local.create_nlb ? 1 : 0

  name        = local.resource_name
  port        = var.target_port
  protocol    = "TCP"
  target_type = local.target_type
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
    port     = var.target_port
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "this" {
  count = local.create_nlb ? length(local.targets) : 0

  target_group_arn = aws_lb_target_group.this[0].arn
  target_id        = local.targets[count.index]
  port             = var.target_port
}

resource "aws_lb_listener" "this" {
  count = local.create_nlb ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  tags = local.tags
}

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = var.acceptance_required
  network_load_balancer_arns = [local.nlb_arn]
  allowed_principals         = [var.neuralsec_principal_arn]
  # AWS reports the service's home region among its supported regions, so the
  # pair is the home region and the Neuralsec region we add: a remote consumer
  # connects, and a plan after the apply shows no change.
  supported_regions = local.cross_region ? sort([data.aws_region.current.name, var.neuralsec_region]) : null

  tags = local.tags

  # Terraform 1.4 does not allow one variable's validation to read another, so
  # the cross-variable rule lives here: the endpoint service always exists, and
  # a plan that sets both target kinds or neither must not reach AWS.
  lifecycle {
    precondition {
      condition = (
        var.existing_nlb_arn != null ||
        ((length(var.target_ips) > 0) != (length(var.target_instance_ids) > 0))
      )
      error_message = "Set exactly one of target_ips and target_instance_ids, unless existing_nlb_arn is set."
    }
  }
}
