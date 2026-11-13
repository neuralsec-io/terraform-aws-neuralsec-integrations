locals {
  # The release this module ships in. Bump it with the release tag: every
  # resource carries it as neuralsec:integration-version, and Neuralsec flags a
  # link whose value is older than the current release.
  integration_version = "0.3.2"

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

  # The load balancer and the security group carry the resource name, which
  # stays within the 32 characters a load balancer name allows. The target
  # group takes a generated name instead: changing the target kind replaces it,
  # and the old group is still there while the new one is created.
  resource_name = "neuralsec-pl-${var.name}"

  create_nlb = var.existing_nlb_arn == null

  # One target kind at a time, in the order of preference: the recommended ALB
  # first, then instance ids, then fixed IPs.
  target_type = (
    var.target_alb_arn != null ? "alb" :
    length(var.target_instance_ids) > 0 ? "instance" : "ip"
  )

  # One attachment per target, of exactly one kind: the precondition below
  # rejects a plan that sets more than one or none. The single ALB attachment
  # carries the load balancer ARN, which is why an ALB keeps working while its
  # addresses change.
  targets = local.create_nlb ? (
    var.target_alb_arn != null ? [var.target_alb_arn] : (
      length(var.target_instance_ids) > 0 ? var.target_instance_ids : var.target_ips
    )
  ) : []

  # Terraform 1.4 does not allow one variable's validation to read another, so
  # the cross-variable rule lives in a precondition below. This local counts
  # the target kinds without a branch for each combination.
  target_kinds_set = length([
    for is_set in [
      var.target_alb_arn != null,
      length(var.target_ips) > 0,
      length(var.target_instance_ids) > 0,
    ] : is_set if is_set
  ])

  # The load balancer accepts connections only on 443 (and 80 when http_target_port is set), so its egress is scoped
  # to the targets on the target port. Instance targets and an ALB can move
  # within the VPC, so their rule covers the VPC CIDR; fixed IPs are named one
  # by one.
  egress_cidrs = local.create_nlb ? (
    var.target_alb_arn != null || length(var.target_instance_ids) > 0 ? [data.aws_vpc.this[0].cidr_block] : [
      for address in var.target_ips : "${address}/32"
    ]
  ) : []

  # PrivateLink traffic comes from the Neuralsec endpoint network interfaces,
  # not from an address the customer can name, so the module turns the inbound
  # rule enforcement off and needs no ingress rule.
  cross_region = var.neuralsec_region != data.aws_region.current.name

  # Optional plain HTTP: a second listener on 80 and its own target group on
  # http_target_port, only on the load balancer this module creates.
  http_enabled = local.create_nlb && var.http_target_port != null

  # Egress ports of the load balancer security group: the target port, plus the
  # HTTP target port when enabled and different (a duplicate rule is refused).
  egress_ports = toset(concat(
    [var.target_port],
    local.http_enabled ? [var.http_target_port] : [],
  ))

  # One egress rule per port and target address.
  egress_rules = {
    for pair in setproduct(local.egress_ports, toset(local.egress_cidrs)) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
  }

  # A supplied load balancer wins; otherwise the one this module creates.
  nlb_arn = one(concat(
    [for load_balancer in aws_lb.this : load_balancer.arn],
    var.existing_nlb_arn == null ? [] : [var.existing_nlb_arn],
  ))
}

data "aws_region" "current" {}

# Only instance and ALB targets need the VPC CIDR: an ALB's addresses move
# inside the VPC. IP targets and a supplied load balancer need no VPC read.
data "aws_vpc" "this" {
  count = local.create_nlb && (length(var.target_instance_ids) > 0 || var.target_alb_arn != null) ? 1 : 0

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
    for_each = local.create_nlb ? local.egress_rules : {}

    content {
      from_port   = egress.value.port
      to_port     = egress.value.port
      protocol    = "tcp"
      cidr_blocks = [egress.value.cidr]
      description = "Neuralsec private link to the service on the target port"
    }
  }

  tags = local.tags
}

resource "aws_lb_target_group" "this" {
  count = local.create_nlb ? 1 : 0

  # The name is generated rather than taken from local.resource_name, so a plan
  # that changes the target kind can create the new group before the old one is
  # deleted; with a fixed name AWS would refuse the second group. The Name tag
  # in local.tags keeps the link name.
  name_prefix = "nspl-"
  port        = var.target_port
  protocol    = "TCP"
  target_type = local.target_type
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  # An ALB target group takes a TCP protocol and the ALB listener port, but
  # AWS requires an HTTP or HTTPS health check for it: HTTPS on the listener
  # port, so any answer below 500 proves the ALB is up, whatever the service
  # behind it answers.
  dynamic "health_check" {
    for_each = local.target_type == "alb" ? [1] : []

    content {
      protocol = "HTTPS"
      port     = var.target_port
      path     = "/"
      matcher  = "200-499"
    }
  }

  dynamic "health_check" {
    for_each = local.target_type == "alb" ? [] : [1]

    content {
      protocol = "TCP"
      port     = var.target_port
    }
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "this" {
  count = local.create_nlb ? length(local.targets) : 0

  target_group_arn = aws_lb_target_group.this[0].arn
  target_id        = local.targets[count.index]
  port             = var.target_port
}

# Optional plain HTTP, off by default: same target kind and registration as the
# 443 path, on http_target_port. An ALB target needs an HTTP health check, as
# above; every other kind uses TCP.
resource "aws_lb_target_group" "http" {
  count = local.http_enabled ? 1 : 0

  name_prefix = "nsph-"
  port        = var.http_target_port
  protocol    = "TCP"
  target_type = local.target_type
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  dynamic "health_check" {
    for_each = local.target_type == "alb" ? [1] : []

    content {
      protocol = "HTTP"
      port     = var.http_target_port
      path     = "/"
      matcher  = "200-499"
    }
  }

  dynamic "health_check" {
    for_each = local.target_type == "alb" ? [] : [1]

    content {
      protocol = "TCP"
      port     = var.http_target_port
    }
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "http" {
  count = local.http_enabled ? length(local.targets) : 0

  target_group_arn = aws_lb_target_group.http[0].arn
  target_id        = local.targets[count.index]
  port             = var.http_target_port
}

resource "aws_lb_listener" "http" {
  count = local.http_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http[0].arn
  }

  tags = local.tags
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
  # a plan that sets more than one target kind, none, or an ALB target next to
  # existing_nlb_arn must not reach AWS. target_ips and target_instance_ids
  # alongside existing_nlb_arn are accepted and ignored, because they only feed
  # the load balancer this module creates.
  lifecycle {
    precondition {
      condition = (
        var.existing_nlb_arn != null ? var.target_alb_arn == null : local.target_kinds_set == 1
      )
      error_message = "Set exactly one of target_alb_arn, target_ips and target_instance_ids, or existing_nlb_arn without target_alb_arn. target_ips and target_instance_ids are ignored with existing_nlb_arn."
    }
  }
}
