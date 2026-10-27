# cloud-scanner-role

Read-only role the Neuralsec broker assumes in a customer account, trusted only by the broker with the ExternalId of the connection.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `external_id` | string | required | ExternalId of the connection, `neuralsec-` plus 32 hex characters |
| `neuralsec_broker_arn` | string | required | ARN of the Neuralsec broker role |
| `eks_clusters` | list(string) | `[]` | EKS cluster names that get a view-only access entry |

## Outputs

| Name | Description |
| :--- | :--- |
| `role_arn`, `role_name` | The scanner role |
| `eks_rbac_group` | Kubernetes group set on the access entries, `neuralsec:scanner-rbac-view` |
| `eks_rbac_manifest_path` | Path of `kubernetes/scanner-rbac-view.yaml` |

## EKS and RBAC objects

For each cluster in `eks_clusters` the module creates an access entry with `AmazonEKSViewPolicy` and the Kubernetes group `neuralsec:scanner-rbac-view`. `AmazonEKSViewPolicy` does not cover `rbac.authorization.k8s.io`, and `AmazonEKSAdminViewPolicy` would, but it can also read Secrets, so the module does not use it.

Instead, apply the shipped manifest once per cluster:

```
kubectl apply -f kubernetes/scanner-rbac-view.yaml
```

It creates ClusterRole `neuralsec-scanner-rbac-view` (list on roles, rolebindings, clusterroles and clusterrolebindings; no Secrets, no ConfigMaps, no wildcards) and a ClusterRoleBinding to the group. Without it the scanner still inventories everything else and reports no RBAC objects for the cluster.

The manifest is applied outside Terraform on purpose: a submodule that declares its own `kubernetes` provider cannot be used with `for_each` or `count`, and one provider configuration per cluster would force every caller to wire cluster endpoints and credentials. A plain manifest works with any GitOps or kubectl flow.
