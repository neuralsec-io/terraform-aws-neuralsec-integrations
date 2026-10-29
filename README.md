# Neuralsec integrations

Terraform modules for installing Neuralsec into an AWS account or an AWS Organization. Published as `neuralsec-io/neuralsec-integrations/aws`; each component is a Registry submodule.

## Requirements

| Name | Version |
| :--- | :--- |
| Terraform | >= 1.4 |
| OpenTofu | >= 1.6 |
| AWS provider | >= 5.34 for `cloud-scanner-role` (EKS access entries), >= 4.0 for the other modules |

`sensor-lambda` needs Terraform >= 1.6 or OpenTofu >= 1.6, and AWS provider
>= 5.0, < 7.0. `sensor-eks` needs Helm provider >= 2.17, < 4.0; every other
module works at the floors above.

There is no upper bound. Each module declares its own requirement and
`terraform/compat/` holds the minimum-version check CI runs against them.

## Modules

| Module | What it creates |
| :--- | :--- |
| `modules/cloud-scanner-role` | read-only role per customer account, trusted only by the Neuralsec broker with the ExternalId of the connection; for EKS it also ships a read-only RBAC ClusterRole manifest to apply per cluster |
| `modules/cloud-scanner-org` | read-only role for the management or delegated administrator account, with the `organizations` read actions |
| `modules/cloud-scanner-org/org-rollout` | `cloud-scanner-role` in every active account of an organization, for OpenTofu or plain Terraform |
| `modules/policy` | the action list export and the chunker that splits it across managed policies |
| `modules/sensor-lambda` | no resources: the Neuralsec sensor layer ARN and the environment merged into a customer Lambda function (wrapper or preload mode) |
| `modules/sensor-ecs-sidecar` | no resources: an ECS task definition rewritten with the Neuralsec sensor init and sidecar containers, the shared volume and the PID mode |
| `modules/sensor-eks` | a Helm release of the Neuralsec sensor chart, which runs the DaemonSet on every Linux node of the cluster |
| `modules/sensor-ec2` | an SSM Command document and association that install the Neuralsec sensor on EC2 instances through SSM |

Source addresses use the Registry form:

```hcl
module "cloud_scanner_role" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/cloud-scanner-role"
  version = "0.1.0"

  external_id          = var.external_id
  neuralsec_broker_arn = var.neuralsec_broker_arn
}
```

The repository root is a placeholder module with no resources, inputs or outputs. Use a submodule.

## Tests

```
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked AWS provider, so they need no credentials and make no API calls. Each submodule keeps its inputs and outputs unchanged across releases; the Neuralsec setup instructions read them to render customer setup.
