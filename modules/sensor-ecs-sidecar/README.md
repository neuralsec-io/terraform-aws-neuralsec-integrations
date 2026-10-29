# sensor-ecs-sidecar

Rewrites an ECS task definition to add the Neuralsec sensor. It creates no
resources: it appends two containers to your container definitions and returns
the JSON, the volume and the PID mode you put in your own
`aws_ecs_task_definition`. Fields the module does not rewrite are copied
unchanged, and absent fields stay absent.

- `neuralsec-sensor-init` is non-essential. It copies both hook builds into the
  shared `neuralsec-sensor-lib` volume and exits. The instrumented app
  containers depend on it with `COMPLETE`, which proceeds whatever its exit
  code, so a failed copy can never keep the app from starting. Nothing depends
  on the second container.
- `neuralsec-sensor` is non-essential. It runs the process observer and, when
  `enable_ptrace` is set, the event-only tracer. Only this container gets
  `SYS_PTRACE`, and only when the tracer is enabled. It receives the sensor
  endpoint as `RUNTIME_SENSOR_ENDPOINT`.

App containers named in `app_containers` get the shared volume mounted read
only, the fail-open dependency, and the hook in `LD_PRELOAD` when `libc` names
their build. An existing `LD_PRELOAD` is kept and the hook is appended with
`:`. Containers with `libc = "none"` (or no entry) keep their environment
exactly as it was.

CPU: ECS turns each container's `cpu` into a CPU share weight, and both sensor
containers request the minimum (2). Set `cpu` explicitly on every instrumented
app container (task CPU minus 2 per sensor container) so the app keeps the vCPU
and the sidecar only runs on what is left. The module never changes a customer
container's `cpu`.

## Security settings

- The sensor containers are non-essential, so a sensor failure never stops the
  task.
- `SYS_PTRACE` is added to `neuralsec-sensor` only, and only while
  `enable_ptrace` is true.
- The app containers mount the shared volume read only.
- `pid_mode` is `task` only while the observer or tracer runs.

Requires Terraform >= 1.4 or OpenTofu >= 1.6, and AWS provider >= 4.0.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `container_definitions` | string | required | The task's container definitions as a JSON string |
| `app_containers` | list(string) | required | Names of the containers to instrument; others are untouched |
| `endpoint` | string | required | Sensor endpoint, an `https://` URL, given to the sidecar as `RUNTIME_SENSOR_ENDPOINT` |
| `sidecar_image` | string | `public.ecr.aws/neuralsec/sensor-ecs` | Sensor sidecar image, digest pinned as `repository@sha256:<64 hex>` |
| `libc` | map(string) | `{}` | Container name to hook build: `glibc`, `musl` or `none` |
| `enable_observer` | bool | `true` | Run the process observer in the sidecar |
| `enable_ptrace` | bool | `false` | Run the event-only tracer; adds `SYS_PTRACE` to the sidecar only |

`sidecar_image` must carry a digest: the default repository is a name only and
fails validation until you pin it.

## Outputs

| Name | Description |
| :--- | :--- |
| `container_definitions` | The rewritten container definitions, sensor containers appended |
| `pid_mode` | `task` when the observer or tracer needs the shared PID namespace, else `null` |
| `volumes` | Task volumes to merge; the sidecar and app containers share `neuralsec-sensor-lib` |

## Usage

```hcl
locals {
  container_definitions = [
    {
      name      = "app"
      image     = "public.ecr.aws/docker/library/eclipse-temurin:21-jre"
      essential = true
      cpu       = 1022
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
