# sensor-ec2

Installs the Neuralsec sensor on EC2 instances through AWS Systems Manager.
The module creates an SSM Command document and an association that runs it on a
schedule against the instances you target.

The sensor authenticates with the instance role, so the module stores no
secret. An instance needs an instance profile carrying
`AmazonSSMManagedInstanceCore` with the SSM agent running; instances without a
role cannot report and are left untouched by the association.

The install script:

- detects `x86_64` or `aarch64` and downloads
  `<artifact_base_url>/<sensor_version>/neuralsec-sensor-linux-<arch>.tar.gz`
  with `curl`, or `wget` when curl is absent;
- verifies the tarball against `sha256` for the detected architecture and aborts
  on a mismatch;
- installs the binary at `/usr/local/bin/neuralsec-sensor` (mode 0755, owner
  root) and writes `/etc/systemd/system/neuralsec-sensor.service`;
- reloads systemd and enables the unit now.

It is idempotent: when the installed binary's sha256 already matches the pinned
digest the download is skipped, and the unit is rewritten and reloaded on every
run.

The unit reports `RUNTIME_SENSOR_ENDPOINT` and
`RUNTIME_SENSOR_PLATFORM=ec2`, and is hardened:

```
AmbientCapabilities=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE
CapabilityBoundingSet=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/sys/kernel/btf /sys/fs/cgroup /sys/kernel/tracing
MemoryMax=128M
CPUQuota=20%
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
Restart=on-failure
RestartSec=10
StandardOutput=null
```

The host kernel must expose BTF at `/sys/kernel/btf` and tracefs at
`/sys/kernel/tracing`.

With `uninstall = true` the document stops, disables and removes the unit and
the binary instead of installing them; the association is kept, so the removal
runs on the same schedule.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 4.0.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `endpoint` | string | required | Sensor endpoint, an `https://` URL, set as `RUNTIME_SENSOR_ENDPOINT` |
| `sensor_version` | string | required | Sensor build version, the directory under `artifact_base_url` |
| `sha256` | map(string) | required | Expected tarball sha256 per architecture: keys `x86_64` and `aarch64`, 64 lowercase hex characters each |
| `artifact_base_url` | string | `https://downloads.neuralsec.io/sensor` | Base URL of the release artifacts |
| `targets` | list(object({ key = string, values = list(string) })) | instances tagged `neuralsec-sensor=enabled` | SSM association targets |
| `schedule` | string | `rate(30 minutes)` | Schedule expression for the association |
| `uninstall` | bool | `false` | Render the removal document instead of the installer |
| `name_prefix` | string | `neuralsec-sensor` | Prefix for the SSM document name |

## Outputs

| Name | Description |
| :--- | :--- |
| `document_name` | Name of the SSM Command document |
| `association_id` | ID of the SSM association that runs the document |

## Usage

```hcl
module "sensor_ec2" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/sensor-ec2"
  version = "0.3.0"

  endpoint       = "https://sensor.example.com"
  sensor_version = "1.2.3"

  sha256 = {
    x86_64  = "<64 hex>"
    aarch64 = "<64 hex>"
  }

  targets = [
    { key = "tag:neuralsec-sensor", values = ["enabled"] },
  ]
}
```

Tag the instances to instrument with `neuralsec-sensor=enabled`, or pass your
own `targets`. To remove the sensor, set `uninstall = true` and apply, then
destroy the module.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked AWS provider, so they need no credentials and
make no API calls.
