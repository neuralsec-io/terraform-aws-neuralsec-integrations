# sensor-lambda

Wraps a Lambda function for the Neuralsec sensor. It creates no resources: it
computes the environment and the layer list you merge into your own
`aws_lambda_function`, so Terraform stays the single owner of the function
configuration. Removing the module and restoring the function's own variables
and layers takes the sensor off again.

The module works from the function's current `environment` and `layers` and
returns the complete desired values:

- The sensor layer for the function's `region` and `architecture` is appended.
  Any existing sensor layer is replaced, whatever its region, architecture or
  version, in the position of the first one; other layers keep their order and
  duplicates are kept. Adding the layer fails the plan when the function
  already has five layers.
- `mode` defaults to `wrapper` for managed runtimes and `preload` for
  `provided.*` runtimes. With `mode = "wrapper"` the sensor wrapper becomes
  `AWS_LAMBDA_EXEC_WRAPPER`; a wrapper the function already used moves to the
  front of `RUNTIME_SENSOR_CHAIN_WRAPPER` and is recorded in
  `RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER`, so it still runs. With
  `mode = "preload"` the hook (`/opt/lib/libsensor_hook.so`, or
  `/opt/lib/musl/libsensor_hook.so` with `libc = "musl"`) is prepended to
  `LD_PRELOAD`, colon separated and never duplicated. Converting a function in
  wrapper mode to preload restores the migrated wrapper first; a chain with
  more than one entry fails the plan instead of dropping wrappers.
- `endpoint` is returned as `RUNTIME_SENSOR_ENDPOINT` on every path.
- `egress_proxy = true` points `HTTPS_PROXY` and `https_proxy` at the sensor's
  loopback proxy, marks `RUNTIME_SENSOR_PROXY`, and merges the sensor entries
  into `NO_PROXY` and `no_proxy` while keeping every customer entry. A function
  that already defines proxy variables the sensor will not chain to fails the
  plan.
- `warnings` lists conditions worth surfacing to the operator: a `provided.*`
  runtime (the hook cannot load into it), the egress proxy's HTTPS-path risk,
  and a container image whose environment sets `AWS_LAMBDA_EXEC_WRAPPER`
  (which overrides the baked `ENV` line).

Requires Terraform >= 1.6 or OpenTofu >= 1.6, and AWS provider >= 5.0, < 7.0.

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `environment` | map(string) | `{}` | The function's current environment variables; they pass through unchanged |
| `layers` | list(string) | `[]` | The function's current layer ARNs, in order |
| `architecture` | string | `x86_64` | `x86_64` or `arm64`; selects the layer and is validated |
| `runtime` | string | `null` | Runtime identifier, for example `python3.12`; `provided.*` defaults to preload mode |
| `package_type` | string | `Zip` | `Zip` or `Image`; layers do not apply to an image |
| `region` | string | required | Function region, used to look the layer ARN up |
| `endpoint` | string | required | Sensor endpoint, an `https://` URL, returned as `RUNTIME_SENSOR_ENDPOINT` |
| `mode` | string | `null` | `wrapper` or `preload`; null picks the default for the runtime |
| `libc` | string | `glibc` | Hook build used in preload mode: `glibc` or `musl` |
| `egress_proxy` | bool | `false` | Opt in to the extension's egress proxy |

## Outputs

| Name | Description |
| :--- | :--- |
| `environment` | The desired environment variables; unchanged for a container image |
| `layers` | The desired layer ARNs; unchanged for a container image |
| `warnings` | Conditions the caller should surface; none of them blocks the deploy |
| `image_instructions` | For `package_type = "Image"` only: the Dockerfile lines replacing the layer; null for a zip function |

## Usage

```hcl
locals {
  function_environment = { LOG_LEVEL = "info" }
  function_layers      = []
}

module "sensor_lambda" {
  source  = "neuralsec-io/neuralsec-integrations/aws//modules/sensor-lambda"
  version = "0.3.0"

  environment  = local.function_environment
  layers       = local.function_layers
  architecture = "arm64"
  region       = "eu-west-1"
  endpoint     = "https://sensor.example.com"
}

resource "aws_lambda_function" "app" {
  function_name = "app"
  role          = aws_iam_role.app.arn
  runtime       = "python3.12"
  handler       = "handler.main"
  filename      = "handler.zip"
  architectures = ["arm64"]

  environment {
    variables = module.sensor_lambda.environment
  }

  layers = module.sensor_lambda.layers

  # tags, timeout, memory_size, ...
}

output "sensor_warnings" {
  value = module.sensor_lambda.warnings
}
```

Pass the function's current variables and layers in as `environment` and
`layers` instead of reading them from the `aws_lambda_function` resource the
module feeds: a resource that depends on its own module output is a cycle.

## Lambda container images

Layers do not apply to functions deployed as container images. The module then
returns the function's environment unchanged and gives the Dockerfile lines in
`image_instructions`:

```dockerfile
COPY --from=<registry>/sensor-lambda:<version> /opt /opt
ENV RUNTIME_SENSOR_ENDPOINT=https://sensor.example.com
ENV AWS_LAMBDA_EXEC_WRAPPER=/opt/bin/sensor-wrapper
```

Add those lines to your own image, or the preload `ENV LD_PRELOAD` line when
the runtime is `provided.*`. The same function configuration passed to the
module must still carry its own environment so the wrapper and chain are
computed from it.

## Tests

```
# from terraform/
terraform init -backend=false && terraform test
tofu init -backend=false && tofu test
```

The module calls no provider, so the tests need no credentials and make no API
calls.
