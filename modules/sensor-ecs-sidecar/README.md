# sensor-ecs-sidecar

Rewrites an ECS task definition to add the Neuralsec sensor. It creates no
resources: it appends two containers to your container definitions and returns
the JSON, the volumes and the PID mode you put in your own
`aws_ecs_task_definition`. Fields the module does not rewrite are copied
unchanged, and absent fields stay absent.

- `neuralsec-sensor-init` is non-essential. It copies both hook builds into the
  shared `neuralsec-sensor-lib` volume, creates the ring root
  `/opt/neuralsec-sensor/ring` (root owned, mode 1777) and exits. The
  instrumented app containers depend on it with `COMPLETE`, which proceeds
  whatever its exit code, so a failed copy can never keep the app from starting.
  Nothing depends on the second container.
- `neuralsec-sensor` is non-essential. It runs the process observer, the
  event-only tracer when `enable_ptrace` is set, and the ring drain when any
  container gets a hook. Only this container gets `SYS_PTRACE`, and only when the
  tracer is enabled. It receives the sensor endpoint as
  `RUNTIME_SENSOR_ENDPOINT`.

App containers named in `app_containers` get the hook volume mounted read only,
the ring volume mounted read-write at `/opt/neuralsec-sensor/ring`, the fail-open
dependency, and the hook in `LD_PRELOAD` when `libc` names their build. An
existing `LD_PRELOAD` is kept and the hook is appended with `:`. Every hooked
container also gets its own `RUNTIME_SENSOR_SHM_PATH`
`/opt/neuralsec-sensor/ring/<container>/ring.bin`, so containers with different
uids never share a ring; an existing value for that variable is replaced. Each
container creates its ring on first use under its own uid. Containers with
`libc = "none"` (or no entry) keep their environment exactly as it was.

CPU: ECS turns each container's `cpu` into a CPU share weight, and both sensor
containers request the minimum (2). Set `cpu` explicitly on every instrumented
app container (task CPU minus 2 per sensor container) so the app keeps the vCPU
and the sidecar only runs on what is left. The module never changes a customer
container's `cpu`.

## Task role

The task definition needs a task role (`task_role_arn`). The sidecar uses the
task role credentials to presign its requests to the endpoint, so it must be an
IAM role, but the role needs no IAM permissions of its own: an empty role policy
is enough. A task without a task role runs the sidecar without credentials and
the sidecar cannot report.

## Security settings

- The sensor containers are non-essential, so a sensor failure never stops the
  task.
- `SYS_PTRACE` is added to `neuralsec-sensor` only, and only while
  `enable_ptrace` is true.
- The app containers mount the hook volume read only. They mount the ring volume
  read-write because the hook creates their own ring under it; the init
  container creates only the shared root, and the module grants no capability
  for it (the ring root is mode 1777).
- `pid_mode` is `task` whenever a container is hooked or the observer or tracer
  runs, and `null` otherwise.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 4.0.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `container_definitions` | string | required | The task's container definitions as a JSON string |
| `app_containers` | list(string) | required | Names of the containers to instrument; others are untouched |
| `endpoint` | string | required | Sensor endpoint, an `https://` URL, given to the sidecar as `RUNTIME_SENSOR_ENDPOINT` |
| `sidecar_image` | string | required | Sensor sidecar image, digest pinned as `repository@sha256:<64 hex>` |
| `libc` | map(string) | `{}` | Container name to hook build: `glibc`, `musl` or `none` |
| `enable_observer` | bool | `true` | Run the process observer in the sidecar |
| `enable_ptrace` | bool | `false` | Run the event-only tracer; adds `SYS_PTRACE` to the sidecar only |

`sidecar_image` has no default and must carry a digest: a repository name alone
fails validation. Pin the digest you deployed so an image update is an explicit
change.

## Outputs

| Name | Description |
| :--- | :--- |
| `container_definitions` | The rewritten container definitions, sensor containers appended |
| `pid_mode` | `task` when the observer, tracer or ring drain needs the shared PID namespace, else `null` |
| `volumes` | Task volumes to merge; the sensor and app containers share `neuralsec-sensor-lib` (hook builds) and `neuralsec-sensor-ring` (per-container rings) |

## Usage

```hcl
locals {
  container_definitions = [
    {
      name      = "app"
      image     = "public.ecr.aws/docker/library/eclipse-temurin:21-jre"
      essential = true
      cpu       = 1020
      command   = ["java", "-jar", "/app/app.jar"]
      environment = [
        { name = "APP_ENV", value = "prod" },
      ]
    },
  ]
}

module "sensor_ecs_sidecar" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/sensor-ecs-sidecar"
  version = "0.3.0"

  container_definitions = jsonencode(local.container_definitions)
  app_containers        = ["app"]
  sidecar_image         = "public.ecr.aws/neuralsec/sensor-ecs@sha256:<64 hex>"
  endpoint              = "https://sensor.example.com"
  libc                  = { app = "glibc" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "app"
  cpu                      = 1024
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  # Required: the sidecar uses the task role to presign its requests.
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = module.sensor_ecs_sidecar.container_definitions
  volumes               = module.sensor_ecs_sidecar.volumes
  pid_mode              = module.sensor_ecs_sidecar.pid_mode
}
```

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The tests plan against a mocked AWS provider, so they need no credentials and
make no API calls.
