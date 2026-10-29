# sensor-eks

Installs the Neuralsec sensor chart in `helm/neuralsec-sensor` as a Helm
release, which runs the sensor as a DaemonSet on every Linux node of the
cluster.

The module renders the chart values the chart requires and merges the caller's
`values` on top:

- `endpoint` becomes `endpoint`, the ingest endpoint the sensor reports to.
- `cluster_name` becomes `clusterName`, reported with the node metadata.
- `image_digest` becomes `image.digest`, so the image is digest pinned.
- `privileged` becomes `securityContext.privileged`, the fallback for node
  images that refuse a capability-only pod.

`values` is merged last with a shallow merge: a nested key you set replaces the
whole rendered block. For example `values = { image = { pullPolicy = "Always" } }`
replaces the rendered `image` block, so repeat the digest there when you do
that. Every other chart value (`nodeSelector`, `affinity`, `hostPaths`,
`extraEnv`, ...) is available through `values` without a new module input.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and Helm provider >= 2.17, < 4.0.
The provider must point at the cluster the release is installed into.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `endpoint` | string | required | Sensor endpoint, an `https://` URL, rendered as `endpoint` |
| `cluster_name` | string | required | Cluster name reported with the node metadata, rendered as `clusterName` |
| `image_digest` | string | required | Image digest as `sha256:` and 64 lowercase hex characters, rendered as `image.digest` |
| `chart_version` | string | `0.1.0` | Chart version to install |
| `chart_repository` | string | `oci://public.ecr.aws/neuralsec/charts` | OCI repository holding the chart |
| `namespace` | string | `neuralsec` | Namespace the release is installed into |
| `create_namespace` | bool | `true` | Create the namespace when it does not exist |
| `values` | any | `{}` | Extra chart values, merged last over the rendered values |
| `privileged` | bool | `false` | Run the pod privileged, rendered as `securityContext.privileged` |

## Outputs

| Name | Description |
| :--- | :--- |
| `namespace` | Namespace the release is installed into |
| `release_name` | Helm release name |
| `chart_version` | Chart version installed |

## Usage

```hcl
provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

module "sensor_eks" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/sensor-eks"
  version = "0.3.0"

  endpoint     = "https://sensor.example.com"
  cluster_name = "example-cluster"
  image_digest = "sha256:<64 hex>"

  values = {
    nodeSelector = { "kubernetes.io/os" = "linux" }
  }
}
```

The Helm provider block format differs between 2.x and 3.x; the module itself
uses only `helm_release` attributes that both versions share.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked Helm provider, so they need no cluster and no
credentials.
