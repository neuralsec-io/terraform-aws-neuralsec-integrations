# cloud-scanner-role

Read-only role the Neuralsec broker assumes in a customer account, trusted only by the broker with the ExternalId of the connection.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 5.34 for the EKS access entry type.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `external_id` | string | required | ExternalId of the connection, `neuralsec-` plus 32 hex characters |
| `neuralsec_broker_arn` | string | required | ARN of the Neuralsec broker role |
| `eks_clusters` | list(string) | `[]` | EKS cluster names that get a view-only access entry |
| `state_locations` | list(object) | `[]` | Terraform or Pulumi state bucket prefixes the scanner may read: `bucket`, `prefix`, and optionally `tool` (`terraform` or `pulumi`), `region` and `kms_key_arn` |

## Outputs

| Name | Description |
| :--- | :--- |
| `role_arn`, `role_name` | The scanner role |
| `eks_rbac_group` | Kubernetes group set on the access entries, `neuralsec:scanner-rbac-view` |
| `eks_rbac_manifest_path` | Path of `kubernetes/scanner-rbac-view.yaml` |
| `state_location_tags` | Tags on the role that name the registered IaC state locations |
| `iac_state_policy_document` | The scoped IaC state policy, empty when no location is registered |

## IaC state locations

The scanner reads Terraform and Pulumi state files to link cloud resources to the code that declares them. State objects are the one kind of object content Neuralsec may read, and only at the locations you register in `state_locations`:

```hcl
state_locations = [
  { bucket = "example-terraform-state", prefix = "app/prod/" },
  { bucket = "example-pulumi-state", prefix = ".pulumi/stacks/", tool = "pulumi", kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" },
]
```

This input is the grant and the only authoritative list. With it, the module adds a separate managed policy that allows `s3:GetObject` on `arn:aws:s3:::<bucket>/<prefix>*`, one `s3:ListBucket` statement per bucket conditioned to that bucket's registered prefixes, and `kms:Decrypt` on the keys you list, conditioned to the S3 endpoint of the location's region. Nothing else is granted by it, and the account read policy still cannot read object contents. Neuralsec reads the tags below with `iam:GetAccountAuthorizationDetails`, an action the role already has for IAM inventory, so the state policy needs no IAM action of its own. `prefix` defaults to the bucket root and must be a literal prefix (no wildcard characters or template markers), `tool` to `terraform`, and `region` to the provider region. `kms_key_arn` takes a key ARN, not an alias ARN: `kms:Decrypt` is evaluated against the key, so an alias would grant nothing.

The module also writes one numbered tag per location, `neuralsec:state-locations-1`, `-2`, ..., whose value is the standard base64 encoding of `tool`, `region`, `bucket` and `prefix` separated by newlines. That tag is how Neuralsec learns which locations you granted. Base64 is required, not stylistic: IAM accepts only letters, digits and `_ . : / = + - @` in a tag value, so the fields cannot be joined with a separator or escaped. A location typed in the console is only a suggestion and is never read until it is listed here.

A location is removed by removing it from the input: the tag and its grant go with it. Prefixes are limited to 1024 characters, the encoded value to 256 characters (an IAM tag value), and at most 50 locations fit one role. A provider `default_tags` block also tags this role, and those tags count toward the same 50 tag limit; the module cannot see them, so leave room for them in the location count.

## EKS and RBAC objects

For each cluster in `eks_clusters` the module creates an access entry with `AmazonEKSViewPolicy` and the Kubernetes group `neuralsec:scanner-rbac-view`. `AmazonEKSViewPolicy` does not cover `rbac.authorization.k8s.io`, and `AmazonEKSAdminViewPolicy` would, but it can also read Secrets, so the module does not use it.

Instead, apply the shipped manifest once per cluster:

```
kubectl apply -f kubernetes/scanner-rbac-view.yaml
```

It creates ClusterRole `neuralsec-scanner-rbac-view` (list on roles, rolebindings, clusterroles and clusterrolebindings; no Secrets, no ConfigMaps, no wildcards) and a ClusterRoleBinding to the group. Without it the scanner still inventories everything else and reports no RBAC objects for the cluster.

The manifest is applied outside Terraform on purpose: a submodule that declares its own `kubernetes` provider cannot be used with `for_each` or `count`, and one provider configuration per cluster would force every caller to wire cluster endpoints and credentials. A plain manifest works with any GitOps or kubectl flow.
