# Neuralsec integrations

Terraform modules for installing Neuralsec into an AWS account or an AWS Organization. Published as `neuralsec-io/neuralsec-integrations/aws`; each component is a Registry submodule.

## Requirements

| Name | Version |
| :--- | :--- |
| Terraform | >= 1.7.0 |
| OpenTofu | >= 1.7.0 |

Each module declares its own provider requirements.

## Modules

| Module | What it creates |
| :--- | :--- |
| `modules/cloud-scanner-role` | read-only role per customer account, trusted only by the Neuralsec broker with the ExternalId of the connection |
| `modules/cloud-scanner-org` | read-only role for the management or delegated administrator account, with the `organizations` read actions |
| `modules/cloud-scanner-org/org-rollout` | `cloud-scanner-role` in every active account of an organization, for OpenTofu or plain Terraform |
| `modules/policy` | the action list export and the chunker that splits it across managed policies |

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

The tests plan against a mocked AWS provider, so they need no credentials and make no API calls. Each submodule keeps its inputs and outputs unchanged across releases; the app-api manifest reads them to render customer setup instructions.
