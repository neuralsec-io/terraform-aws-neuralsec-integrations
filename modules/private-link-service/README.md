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
| `aws_lb_target_group` | TCP target group, `ip` for `target_ips`, `instance` for `target_instance_ids`, TCP health check on the target port |
| `aws_lb_target_group_attachment` | one entry per target |
| `aws_lb_listener` | TCP 443, forwarded to the target group |
| `aws_vpc_endpoint_service` | endpoint service for the load balancer, `allowed_principals` exactly the Neuralsec role, no private DNS name |

With `existing_nlb_arn` set, it creates only the endpoint service and skips the
load balancer, target group, listener and security group.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `name` | string | required | Name of the link, used in the resource names and the `Name` tag. 1 to 19 letters, digits or hyphens, not starting or ending with a hyphen |
| `neuralsec_org_id` | string | required | Neuralsec organization UUID, tag `neuralsec:org_id` |
| `neuralsec_org_slug` | string | required | Neuralsec organization slug, tag `neuralsec:org_slug` |
| `neuralsec_principal_arn` | string | required | ARN of the Neuralsec IAM role, the only allowed principal |
| `neuralsec_region` | string | required | Region of the Neuralsec consumer, for example `eu-west-1` |
| `vpc_id` | string | required | VPC that holds the service |
| `subnet_ids` | list(string) | required | at least two private subnets the load balancer uses |
| `target_ips` | list(string) | `[]` | private IPv4 addresses of the service. Set exactly one of `target_ips` and `target_instance_ids` unless `existing_nlb_arn` is set |
| `target_instance_ids` | list(string) | `[]` | instance ids of the service. Set exactly one of the two unless `existing_nlb_arn` is set |
| `target_port` | number | `443` | TCP port of the targets. The listener stays on 443 |
| `acceptance_required` | bool | `false` | whether a connection request needs your acceptance |
| `existing_nlb_arn` | string | `null` | ARN of an existing internal Network Load Balancer to publish |
| `tags` | map(string) | `{}` | additional tags for every resource |

## Outputs

| Name | Description |
| :--- | :--- |
| `service_name` | endpoint service name, `com.amazonaws.vpce.<region>.vpce-svc-<id>`; paste it into Neuralsec |
| `endpoint_service_id` | endpoint service id |
| `nlb_arn` | ARN of the load balancer that publishes the service |
| `nlb_security_group_id` | security group to allow on the target port in the service security group; null with `existing_nlb_arn` |

## Tags

Every taggable resource carries the release tags in one map: `neuralsec:component`
(`private-link-service`), `neuralsec:integration-version`, `neuralsec:org_id`,
`neuralsec:org_slug`, `neuralsec:created_at`, `Name`, plus your `tags`. The
created-at value is fixed at the first apply by a `time_static` resource, so it
never drifts. `neuralsec:integration-version` names the release the module
shipped in and is bumped with that release.

## The one manual step

Allow the load balancer security group (`nlb_security_group_id`) on the target
port in the security group of the service itself. The module cannot do it: that
security group belongs to you, not to this module.

## Cross-region

When `neuralsec_region` differs from the region of the stack, the endpoint
service lists both regions in `supported_regions`: your own region (AWS always
reports the service's home region as supported) and the Neuralsec region, so
the Neuralsec endpoint can connect across regions and a later plan shows no
diff. The load balancer and the service stay in your region.

## Usage

```hcl
module "neuralsec_private_link_service" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/private-link-service"
  version = "0.3.0"

  name                    = "registry"
  neuralsec_org_id        = "00000000-0000-4000-8000-000000000000"
  neuralsec_org_slug      = "example"
  neuralsec_principal_arn = "arn:aws:iam::111111111111:role/neuralsec-app"
  neuralsec_region        = "eu-west-1"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  target_ips = ["10.0.1.10", "10.0.2.10"]
}
```

The CloudFormation template `private-link-service.yaml` mirrors the module. It
takes the same values as parameters (`Name`, `NeuralsecOrgId`,
`NeuralsecOrgSlug`, `CreatedAt`, `NeuralsecPrincipalArn`, `NeuralsecRegion`,
`VpcId`, `SubnetIds`, `TargetIp`, `TargetInstanceId`, `TargetPort`,
`AcceptanceRequired`, `ExistingNlbArn`). A stack registers one target, because
CloudFormation cannot turn a parameter list into one target registration per
address; use this module when the service sits behind several addresses.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked AWS and time provider, so they need no
credentials and make no API calls.
