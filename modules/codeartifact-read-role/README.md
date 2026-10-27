# codeartifact-read-role

Role the Neuralsec broker assumes to read an AWS CodeArtifact registry. It
creates the role Neuralsec describes for an `aws_codeartifact` registry, so the
setup instructions and this module render the same role name, inline policy
`neuralsec-codeartifact-read`, trust policy and resource ARNs.

The role is shared on purpose. Every Neuralsec CodeArtifact registry whose
`role_arn` names the same role uses it, and each registry has its own random
ExternalId. The trust policy therefore requires the ExternalId of every
sibling registry, and the inline policy covers every sibling domain. Applying
the template of the latest registry with all of them covers the whole set: when
another registry starts using this role, update the existing stack or module
run instead of creating a second role.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 4.0.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `external_ids` | list(string) | required | ExternalId of every registry that shares the role, `neuralsec-` plus 32 hex characters |
| `neuralsec_broker_arn` | string | required | ARN of the Neuralsec broker role, the only principal allowed to assume this role |
| `role_name` | string | `neuralsec-registry-read` | Role name, the one in the registry role ARN |
| `role_path` | string | `""` | IAM path, the one in the registry role ARN. Empty means `/` |
| `domains` | list(object) | required | `region`, `domain_owner` and `domain` of every sibling registry domain |

## Outputs

| Name | Description |
| :--- | :--- |
| `role_arn` | ARN of the read-only CodeArtifact role the Neuralsec broker assumes |

## Policy

The inline policy holds exactly three statements, the read actions the
broker's Verify and Mint calls use:

- `codeartifact:GetAuthorizationToken` on the domain ARNs.
- `codeartifact:GetRepositoryEndpoint` and `codeartifact:ReadFromRepository`
  on the repository ARNs of those domains.
- `sts:GetServiceBearerToken` on `*`, limited to
  `codeartifact.amazonaws.com`. The action supports no resource-level
  scoping, so it is the only wildcard resource.

The trust policy has one statement: principal the broker ARN, action
`sts:AssumeRole`, condition `sts:ExternalId` equal to every input ExternalId.

## Usage

```hcl
module "codeartifact_read_role" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/codeartifact-read-role"
  version = "0.1.0"

  external_ids         = ["neuralsec-0123456789abcdef0123456789abcdef"]
  neuralsec_broker_arn = "arn:aws:iam::111111111111:role/neuralsec-broker"

  domains = [
    { region = "eu-west-1", domain_owner = "111111111111", domain = "private" },
  ]
}
```

The CloudFormation template `codeartifact-read-role.yaml` mirrors it. It takes
`ExternalIds` as a `CommaDelimitedList`, `NeuralsecBrokerArn`, `RoleName`,
`RolePath`, `DomainArns` and `RepositoryArns`; CloudFormation cannot derive the
repository ARN list from the domain ARN list, so pass both, one entry per
domain.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked AWS provider, so they need no credentials and
make no API calls.
