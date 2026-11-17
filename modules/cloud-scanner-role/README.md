# cloud-scanner-role

Read-only role the Neuralsec broker assumes in a customer account, trusted only by the broker with the ExternalId of the connection.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 5.34 for the EKS access entry type.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `external_id` | string | required | ExternalId of the connection, `neuralsec-` plus 32 hex characters |
| `neuralsec_broker_arn` | string | required | ARN of the Neuralsec broker role |
| `eks_clusters` | list(string) | `[]` | EKS cluster names that get a scanner access entry, bound to the list-only ClusterRole you apply |
| `eks_view_policy_association` | bool | `true` | Keep the broader `AmazonEKSViewPolicy` association for this release; set `false` once the list-only ClusterRole is applied |
| `state_locations` | list(object) | `[]` | Terraform or Pulumi state bucket prefixes the scanner may read: `bucket`, `prefix`, and optionally `tool` (`terraform` or `pulumi`), `region`, `kms_key_arn`, `whole_bucket` and `bucket_owner` |

## Outputs

| Name | Description |
| :--- | :--- |
| `role_arn`, `role_name` | The scanner role |
| `eks_rbac_group` | Kubernetes group set on the access entries, `neuralsec:scanner-rbac-view` |
| `eks_rbac_manifest_path` | Path of `kubernetes/scanner-rbac-view.yaml` |
| `scanner_egress_ipv6_cidrs` | IPv6 `/56` the scanner connects from, for a dual-stack (`ipv6`) cluster created after October 2024 |
| `scanner_egress_ipv4_cidrs` | Fixed IPv4 addresses the scanner connects from, one `/32` each, for every cluster |
| `scanner_egress_cidrs` | Both families, IPv6 first: the whole list to allow on a dual-stack cluster created after October 2024 |
| `state_location_tags` | Tags on the role that name the registered IaC state locations |
| `iac_state_policy_document` | The scoped IaC state policy, empty when no location is registered |

## Read policies

The role lists every action, because it cannot use action wildcards, so the read actions are split across up to six managed policies named `neuralsec-cloud-scanner-read-01` to `-06`. Each service goes to one fixed policy (a stable hash of the service name), so a new action changes only the one policy that holds its service, and every other policy stays as it was. The number of buckets is fixed at six and never changes. Only when a policy would pass its size budget do some of its services move to the next policy; that is the one case in which a new action can move other actions too. A service moves at most six times; if the actions still do not fit six policies of 5120 bytes the plan fails with a "Spill overflow" error, and Neuralsec ships a new release. An empty bucket creates no policy and the other policies keep their numbers.

With every feature on, the role holds the six read policies, the deny policy and the IaC state policy: eight managed policies, which leaves two of the default limit of ten for your own policies. The plan fails with a message if the list ever needs more than the room it has.

Upgrading to this version moves actions between the read policies once. The apply updates the policies in place and the role keeps the same permissions. CloudFormation and Terraform cut identical policies.

## IaC state locations

The scanner reads Terraform and Pulumi state files to link cloud resources to the code that declares them. State objects are the one kind of object content Neuralsec may read, and only at the locations you register in `state_locations`:

```hcl
state_locations = [
  { bucket = "example-terraform-state", prefix = "app/prod/" },
  { bucket = "example-pulumi-state", prefix = ".pulumi/stacks/", tool = "pulumi", kms_key_arn = "arn:aws:kms:eu-west-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" },
]
```

This input is the grant and the only authoritative list. With it, the module adds a separate managed policy that allows `s3:GetObject` on `arn:aws:s3:::<bucket>/<prefix>*`, one `s3:ListBucket` statement per bucket conditioned to that bucket's registered prefixes, and `kms:Decrypt` on the keys you list, conditioned to the S3 endpoint of the location's region. Nothing else is granted by it, and the account read policy still cannot read object contents. Neuralsec reads the tags below with `iam:GetAccountAuthorizationDetails`, an action the role already has for IAM inventory, so the state policy needs no IAM action of its own. `prefix` must be a literal prefix ending in `/` or an exact object key ending in `.tfstate` for `tool = "terraform"` or `.json` for `tool = "pulumi"` (no wildcard characters or template markers); an exact key is granted as that one object. To read a whole bucket set `whole_bucket = true` and leave `prefix` empty; an empty prefix without it is rejected. Every S3 grant carries an `aws:ResourceAccount` condition: the account of this role by default, or `bucket_owner` for a bucket owned by another account (set it when the state bucket lives in a central account, also in `org-rollout`). `kms:Decrypt` is one statement per key, also conditioned on the registered buckets and prefixes through `kms:EncryptionContext:aws:s3:arn`.

`tool` defaults to `terraform`, and `region` to the provider region. `kms_key_arn` takes a key ARN, not an alias ARN: `kms:Decrypt` is evaluated against the key, so an alias would grant nothing.

The module also writes one numbered tag per location, `neuralsec:state-locations-1`, `-2`, ..., whose value is the standard base64 encoding of `tool`, `region`, `bucket` and `prefix` separated by newlines. That tag is how Neuralsec learns which locations you granted. Base64 is required, not stylistic: IAM accepts only letters, digits and `_ . : / = + - @` in a tag value, so the fields cannot be joined with a separator or escaped. A location typed in the console is only a suggestion and is never read until it is listed here.

A location is removed by removing it from the input: the tag and its grant go with it. Prefixes are limited to 1024 characters, the encoded value to 256 characters (an IAM tag value), and at most 50 locations fit one role. A provider `default_tags` block also tags this role, and those tags count toward the same 50 tag limit; the module cannot see them, so leave room for them in the location count.

## EKS access

For each cluster in `eks_clusters` the module creates an access entry that puts the role in the Kubernetes group `neuralsec:scanner-rbac-view`. The intended grant is the ClusterRole in the shipped manifest, which you apply once per cluster:

```
kubectl apply -f kubernetes/scanner-rbac-view.yaml
```

It creates ClusterRole `neuralsec-scanner-rbac-view` and a ClusterRoleBinding to the group. The ClusterRole grants only the verb `list`, across all namespaces, on:

| API group | Resources |
| :--- | :--- |
| `apps` | `deployments`, `statefulsets`, `daemonsets` |
| `batch` | `cronjobs` |
| core | `pods`, `services`, `serviceaccounts` |
| `networking.k8s.io` | `ingresses` |
| `rbac.authorization.k8s.io` | `roles`, `clusterroles`, `rolebindings`, `clusterrolebindings` |

No Secrets, no ConfigMaps, no `get` or `watch`, no wildcards.

`AmazonEKSViewPolicy` also reads ConfigMaps, pod logs and more than the scanner needs, so the module associates it only while `eks_view_policy_association` is `true`, which is the default in this release so that no cluster loses data on upgrade. To move to the list-only grant:

1. Upgrade the module, then apply `kubernetes/scanner-rbac-view.yaml` to every cluster in `eks_clusters`. The manifest of earlier releases only granted RBAC objects, so apply the new one.
2. Set `eks_view_policy_association = false`.

The default changes to `false` in the next minor release. If you leave the default and the manifest is not applied then, the scanner loses the workload inventory of that cluster until you apply it. While the association is on, the output `eks_upgrade_notice` carries this instruction. Re-export `eks_upgrade_notice` from your root module (`output "eks_upgrade_notice" { value = module.cloud_scanner_role.eks_upgrade_notice }`, using your module name) so the notice shows after every apply.

The manifest is applied outside Terraform on purpose: the module cannot create Kubernetes objects itself, because a submodule that declares its own `kubernetes` provider cannot be used with `for_each` or `count`, and one provider configuration per cluster would force every caller to wire cluster endpoints and credentials. A plain manifest works with any GitOps or kubectl flow. The path is the `eks_rbac_manifest_path` output.

## EKS public endpoint allow list

The scanner connects to the Kubernetes API from two address families. It prefers IPv6 towards a dual-stack endpoint, and falls back to IPv4.

| Family | Address | Allowed on |
| :--- | :--- | :--- |
| IPv6 | `2a05:d018:e21:f00::/56` | a dual-stack (`ipv6`) cluster created after October 2024 |
| IPv4 | `3.248.10.74/32`, `34.241.8.107/32`, `52.16.218.0/32` | every cluster |

The module exposes them as `scanner_egress_ipv6_cidrs`, `scanner_egress_ipv4_cidrs` and `scanner_egress_cidrs` (both families, IPv6 first). A dual-stack (`ipv6`) cluster created after October 2024 accepts IPv4 and IPv6 CIDRs in the same `public_access_cidrs` list, and its default is `0.0.0.0/0` plus `::/0`, so allow the whole `scanner_egress_cidrs` there: the scanner prefers IPv6 and falls back to IPv4. Every other cluster (IPv4, or an `ipv6` cluster created before October 2024) accepts IPv4 CIDRs only, so allow `scanner_egress_ipv4_cidrs`.

Check the family of an existing cluster:

```
aws eks describe-cluster --name example-cluster --region eu-west-1 \
  --query 'cluster.kubernetesNetworkConfig.ipFamily'
```

A dual-stack cluster created after October 2024 takes both families; every other cluster takes the three `/32`s.

For a dual-stack IPv6 cluster created after October 2024 in the same configuration:

```hcl
module "cloud_scanner_role" {
  source = "neuralsec-io/neuralsec-integrations/aws//modules/cloud-scanner-role"
  # ...
}

resource "aws_eks_cluster" "this" {
  # ...
  kubernetes_network_config {
    ip_family = "ipv6"
  }
  vpc_config {
    endpoint_public_access = true
    # Append the scanner addresses to the CIDRs you already allow.
    public_access_cidrs = concat(["2001:db8:1234:5600::/56", "198.51.100.0/24"], module.cloud_scanner_role.scanner_egress_cidrs)
  }
}
```

For every other cluster (IPv4, or an IPv6 cluster created before October 2024):

```hcl
resource "aws_eks_cluster" "this" {
  # ...
  vpc_config {
    endpoint_public_access = true
    # Append the scanner addresses to the CIDRs you already allow.
    public_access_cidrs = concat(["198.51.100.0/24"], module.cloud_scanner_role.scanner_egress_ipv4_cidrs)
  }
}
```

If the cluster is not managed by the configuration that calls this module, apply the matching list to the existing cluster with `aws eks update-cluster-config`. `publicAccessCidrs` replaces the whole list, so append the scanner CIDRs to the CIDRs you already allow instead of replacing them.

A cluster with `endpoint_public_access = false` has no public endpoint, so no allow list can reach it from outside. The scanner reports such a cluster as `kubernetes_api_unreadable`; reading the Kubernetes API from inside the VPC is planned. The rest of the cluster's AWS metadata is still inventoried.
