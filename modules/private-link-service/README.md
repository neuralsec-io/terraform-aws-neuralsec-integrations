# private-link-service

Publishes a private HTTPS service, such as a package registry, to Neuralsec
over AWS PrivateLink. It creates an internal Network Load Balancer in your VPC,
a TCP target group, a listener and an endpoint service whose only allowed
principal is the Neuralsec role. TLS stays end to end: the load balancer does
not terminate it, so the service presents its own certificate for the hostname.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, AWS provider >= 5.79.0 (the first
release with `supported_regions` on `aws_vpc_endpoint_service`) and the
`hashicorp/time` provider >= 0.9.0.

## What it creates

| Resource | What it is for |
| :--- | :--- |
| `aws_lb` | internal Network Load Balancer in `subnet_ids`, with a dedicated security group |
| `aws_security_group` | outbound traffic on the target port to the targets; no inbound rule |
| `aws_lb_target_group` | TCP target group, `alb` for `target_alb_arn`, `instance` for `target_instance_ids`, `ip` for `target_ips`; a TCP health check on the target port, or an HTTPS one on the ALB listener port for an ALB target |
| `aws_lb_target_group_attachment` | one entry per target; the single ALB entry carries the load balancer ARN |
| `aws_lb_listener` | TCP 443, forwarded to the target group; with `http_target_port` also TCP 80, forwarded to a second target group (`http`) on that port with the same targets and a TCP health check (HTTP for an ALB target) |
| `aws_vpc_endpoint_service` | endpoint service for the load balancer, `allowed_principals` exactly the Neuralsec role, no private DNS name |

With `existing_nlb_arn` set, it creates only the endpoint service and skips the
load balancer, target group, listener and security group. In that mode
`http_target_port` has no effect: add the TCP 80 listener to your load balancer
yourself.

## Plain HTTP

Set `http_target_port` to also accept plain HTTP on port 80. Plain HTTP is
supported only through this private connection, on port 80. Prefer HTTPS. The
443 listener is unchanged.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `name` | string | required | Name of the link, used in the resource names and the `Name` tag. 1 to 19 letters, digits or hyphens, not starting or ending with a hyphen |
| `neuralsec_org_id` | string | required | Neuralsec organization UUID, tag `neuralsec:org_id` |
| `neuralsec_org_slug` | string | required | Neuralsec organization slug, tag `neuralsec:org_slug` |
| `neuralsec_principal_arn` | string | required | ARN of the Neuralsec IAM role, the only allowed principal |
| `neuralsec_region` | string | `eu-west-1` | Region Neuralsec runs in, left unset; listed next to the stack region when it differs |
| `vpc_id` | string | required | VPC that holds the service |
| `subnet_ids` | list(string) | required | at least two private subnets the load balancer uses |
| `target_alb_arn` | string | `null` | ARN of an internal Application Load Balancer, the recommended target: it keeps a stable ARN while its addresses change. Set exactly one of `target_alb_arn`, `target_ips` and `target_instance_ids`, or `existing_nlb_arn` instead, which rejects an ALB target |
| `target_ips` | list(string) | `[]` | private IPv4 addresses of the service. Set exactly one of `target_alb_arn`, `target_ips` and `target_instance_ids` unless `existing_nlb_arn` is set, which ignores them |
| `target_instance_ids` | list(string) | `[]` | instance ids of the service. Set exactly one of the three unless `existing_nlb_arn` is set, which ignores them |
| `target_port` | number | `443` | TCP port of the targets. The listener on 443 is HTTPS. With `target_alb_arn` it must be the port of an ALB listener, so a health check reaches the ALB |
| `http_target_port` | number | `null` | optional TCP port of the targets for plain HTTP. When set, the load balancer also listens on TCP 80 and forwards to it. Plain HTTP is supported only through this private connection, on port 80. Prefer HTTPS. Ignored with `existing_nlb_arn` |
| `acceptance_required` | bool | `true` | whether a connection request needs your acceptance, so you can confirm the request's endpoint ID matches the one shown in the Neuralsec app for this connection. Set `false` only if you accept that any Neuralsec connection using this service name is accepted automatically |
| `existing_nlb_arn` | string | `null` | ARN of an existing internal Network Load Balancer to publish; `target_ips` and `target_instance_ids` are ignored with it and an ALB target is rejected |
| `tags` | map(string) | `{}` | additional tags for every resource |

## Outputs

| Name | Description |
| :--- | :--- |
| `service_name` | endpoint service name, `com.amazonaws.vpce.<region>.vpce-svc-<id>`; paste it into Neuralsec |
| `endpoint_service_id` | endpoint service id |
| `nlb_arn` | ARN of the load balancer that publishes the service |
| `nlb_security_group_id` | security group to allow on the target port in the service security group; null with `existing_nlb_arn` |
| `load_balancer_security_group_id` | the same security group under a target-neutral name: an Application Load Balancer target must allow it inbound on the target port; null with `existing_nlb_arn` |

## Tags

Every taggable resource carries the release tags in one map: `neuralsec:component`
(`private-link-service`), `neuralsec:integration-version`, `neuralsec:org_id`,
`neuralsec:org_slug`, `neuralsec:created_at`, `Name`, plus your `tags`. The
created-at value is fixed at the first apply by a `time_static` resource, so it
never drifts. `neuralsec:integration-version` names the release the module
shipped in and is bumped with that release.

## The one manual step

Allow the load balancer security group (`nlb_security_group_id` or
`load_balancer_security_group_id`) on the target port in the security group of
the service itself. With `target_alb_arn`, also allow that group inbound on the
target port in the security group of the Application Load Balancer. The module
cannot do it: those security groups belong to you, not to this module.

## Accept the connection

With the default `acceptance_required = true`, Neuralsec's connection request
waits for you. After you paste the service name into Neuralsec, the app shows
the endpoint ID of the request for this connection. In the VPC console, open
Endpoint services, select the service, then Endpoint connections, and accept
only the request whose endpoint ID matches the one in the app. Reject any other
request.

## Cross-region

Neuralsec runs in `eu-west-1`, which is the default of `neuralsec_region`: leave
the input unset. When it differs from the region of the stack, the endpoint
service lists both regions in `supported_regions`: your own region (AWS always
reports the service's home region as supported) and the Neuralsec region, so
the Neuralsec endpoint can connect across regions and a later plan shows no
diff. The load balancer and the service stay in your region.

## Usage

An internal Application Load Balancer is the recommended target: the load
balancer keeps a stable ARN while its IP addresses change, and it can route on
the hostname or path. The target port must be the port of an ALB listener.

```hcl
module "neuralsec_private_link_service" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/private-link-service"
  version = "0.3.2"

  name                    = "registry"
  neuralsec_org_id        = "00000000-0000-4000-8000-000000000000"
  neuralsec_org_slug      = "example"
  neuralsec_principal_arn = "arn:aws:iam::111111111111:role/neuralsec-privatelink"

  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  target_alb_arn = "arn:aws:elasticloadbalancing:eu-west-1:111111111111:loadbalancer/app/registry/0123456789abcdef"
}
```

Fixed IPs work the same way. Prefer the ALB when the service's addresses can
change: a fixed IP that moves breaks the link silently.

```hcl
module "neuralsec_private_link_service" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/private-link-service"
  version = "0.3.2"

  name                    = "registry"
  neuralsec_org_id        = "00000000-0000-4000-8000-000000000000"
  neuralsec_org_slug      = "example"
  neuralsec_principal_arn = "arn:aws:iam::111111111111:role/neuralsec-privatelink"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  target_ips = ["10.0.1.10", "10.0.2.10"]
}
```

The CloudFormation template `private-link-service.yaml` mirrors the module. It
takes the same values as parameters (`Name`, `NeuralsecOrgId`,
`NeuralsecOrgSlug`, `CreatedAt`, `NeuralsecPrincipalArn`, `NeuralsecRegion`,
`VpcId`, `SubnetIds`, `TargetAlbArn`, `TargetIp`, `TargetInstanceId`,
`TargetPort`, `HttpTargetPort`, `AcceptanceRequired`, `ExistingNlbArn`). A stack registers one
target, because CloudFormation cannot turn a parameter list into one target
registration per address; use this module when the service sits behind several
addresses.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests run against a mocked AWS and time provider, so they need no
credentials and make no API calls.
