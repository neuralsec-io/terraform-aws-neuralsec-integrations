# sensor-ecs-sidecar module: the task definition rewrite, one run per case.
#
# The base definition carries 20+ fields so the "untouched" test is meaningful.
# The fail-open shape is pinned here: a non-essential init container that copies
# the hook and exits, and an app dependency with COMPLETE (never HEALTHY). The
# module creates no resources, so the test is plan only and needs no
# credentials.

mock_provider "aws" {}

variables {
  container_definitions = <<-JSON
  [
    {
      "name": "app",
      "image": "public.ecr.aws/docker/library/eclipse-temurin:21-jre-alpine",
      "essential": true,
      "cpu": 512,
      "memory": 1024,
      "memoryReservation": 512,
      "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
      "environment": [{"name": "APP_ENV", "value": "prod"}],
      "secrets": [{"name": "TOKEN", "valueFrom": "arn:aws:ssm:eu-west-1:111111111111:parameter/token"}],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/app",
          "awslogs-region": "eu-west-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {"command": ["CMD", "true"], "interval": 30, "timeout": 5, "retries": 3},
      "workingDirectory": "/app",
      "entryPoint": ["/entrypoint.sh"],
      "command": ["serve"],
      "stopTimeout": 30,
      "readonlyRootFilesystem": true,
      "privileged": false,
      "user": "1000",
      "ulimits": [{"name": "nofile", "softLimit": 1024, "hardLimit": 4096}],
      "dockerLabels": {"team": "platform"},
      "startTimeout": 120
    }
  ]
  JSON

  app_containers = ["app"]
  sidecar_image  = "public.ecr.aws/neuralsec/sensor-ecs@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  endpoint       = "https://sensor.example.com"
  libc           = {}
}

run "adds_init_and_observer" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  assert {
    condition     = length(jsondecode(output.container_definitions)) == 3
    error_message = "expected the app plus the init container and the observer"
  }

  assert {
    condition = (
      [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].essential == false
      && contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].command, "--install-lib")
    )
    error_message = "the init container must be non-essential and install the hook"
  }

  assert {
    condition = (
      contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].command, "--observe")
      && !contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].command, "--install-lib")
    )
    error_message = "the observer runs only the observer role; installing belongs to the init container"
  }

  assert {
    condition = (
      jsondecode(output.container_definitions)[0].dependsOn[0].containerName == "neuralsec-sensor-init"
      && jsondecode(output.container_definitions)[0].dependsOn[0].condition == "COMPLETE"
    )
    error_message = "fail-open: the app waits for the init container with COMPLETE, never HEALTHY"
  }

  assert {
    condition = (
      [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].cpu == 2
      && [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].cpu == 2
    )
    error_message = "both sidecar containers must carry the minimum CPU weight (2)"
  }
}

run "observer_gets_the_endpoint" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  assert {
    condition = (
      [for entry in [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].environment : entry.value if entry.name == "RUNTIME_SENSOR_ENDPOINT"][0]
      == "https://sensor.example.com"
    )
    error_message = "the observer container must receive the sensor endpoint as RUNTIME_SENSOR_ENDPOINT"
  }
}

run "endpoint_must_be_https" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    endpoint = "http://sensor.example.com"
  }

  expect_failures = [var.endpoint]
}

run "sidecar_image_must_be_digest_pinned" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    sidecar_image = "public.ecr.aws/neuralsec/sensor-ecs"
  }

  expect_failures = [var.sidecar_image]
}

run "ptrace_cap_only_when_enabled" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    enable_ptrace = true
  }

  assert {
    condition = (
      contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].linuxParameters.capabilities.add, "SYS_PTRACE")
      && contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].command, "--ptrace")
    )
    error_message = "the tracer must add SYS_PTRACE and --ptrace to the observer"
  }

  assert {
    condition     = try([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].linuxParameters, null) == null
    error_message = "the init container must not gain capabilities"
  }

  assert {
    condition     = try(jsondecode(output.container_definitions)[0].linuxParameters, null) == null
    error_message = "the app container must not gain capabilities"
  }
}

run "no_ptrace_cap_when_disabled" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    enable_ptrace = false
  }

  assert {
    condition     = try([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].linuxParameters, null) == null
    error_message = "SYS_PTRACE must only be requested when the tracer is enabled"
  }
}

run "pid_mode_task_when_observer" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    enable_observer = true
  }

  assert {
    condition     = output.pid_mode == "task"
    error_message = "the observer needs the task PID namespace"
  }

  assert {
    condition = (
      length(output.volumes) == 2
      && output.volumes[0].name == "neuralsec-sensor-lib"
      && output.volumes[1].name == "neuralsec-sensor-ring"
    )
    error_message = "the hook volume and the ring volume must be exposed for the task definition"
  }
}

run "observer_disabled_has_init_only" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    enable_observer = false
    enable_ptrace   = false
  }

  assert {
    condition     = length(jsondecode(output.container_definitions)) == 2
    error_message = "with neither observer nor tracer enabled the module appends just the init container"
  }

  assert {
    condition     = try([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0], null) == null
    error_message = "no observer container when neither the observer nor the tracer is enabled"
  }

  assert {
    condition     = output.pid_mode == null
    error_message = "pidMode must stay unset when no role needs the shared PID namespace"
  }

  assert {
    condition     = jsondecode(output.container_definitions)[0].dependsOn[0].condition == "COMPLETE"
    error_message = "a static image still gets the fail-open init dependency"
  }
}

run "existing_ld_preload_preserved_and_appended" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    libc                  = { app = "glibc" }
    container_definitions = <<-JSON
    [
      {
        "name": "app",
        "image": "public.ecr.aws/docker/library/eclipse-temurin:21-jre-alpine",
        "environment": [{"name": "LD_PRELOAD", "value": "/opt/existing.so"}]
      }
    ]
    JSON
  }

  assert {
    condition = (
      [for entry in jsondecode(output.container_definitions)[0].environment : entry.value if entry.name == "LD_PRELOAD"][0]
      == "/opt/existing.so:/opt/neuralsec-sensor/lib/glibc/libsensor_hook.so"
    )
    error_message = "an existing LD_PRELOAD must be kept and the hook appended with a colon"
  }

  assert {
    condition     = length([for entry in jsondecode(output.container_definitions)[0].environment : entry if entry.name == "LD_PRELOAD"]) == 1
    error_message = "appending must replace LD_PRELOAD, not duplicate the variable"
  }
}

run "static_image_gets_no_ld_preload" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    libc = { app = "none" }
  }

  assert {
    condition = !contains(
      [for entry in jsondecode(output.container_definitions)[0].environment : entry.name],
      "LD_PRELOAD"
    )
    error_message = "a static image must not get LD_PRELOAD"
  }

  assert {
    condition = (
      [for entry in jsondecode(output.container_definitions)[0].environment : entry.name]
      == [for entry in jsondecode(var.container_definitions)[0].environment : entry.name]
    )
    error_message = "the environment must be byte-identical when no hook is delivered"
  }

  assert {
    condition = (
      length(jsondecode(output.container_definitions)[0].mountPoints) == 2
      && jsondecode(output.container_definitions)[0].mountPoints[0].readOnly == true
      && jsondecode(output.container_definitions)[0].mountPoints[1].sourceVolume == "neuralsec-sensor-ring"
      && jsondecode(output.container_definitions)[0].mountPoints[1].readOnly == false
      && jsondecode(output.container_definitions)[0].dependsOn[0].condition == "COMPLETE"
    )
    error_message = "a static image still gets both mounts and the fail-open dependency"
  }
}

run "other_fields_untouched" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    libc = { app = "musl" }
  }

  assert {
    condition = alltrue([
      for field in [
        "name", "image", "essential", "cpu", "memory", "memoryReservation",
        "portMappings", "secrets", "logConfiguration", "healthCheck",
        "workingDirectory", "entryPoint", "command", "stopTimeout",
        "readonlyRootFilesystem", "privileged", "user", "ulimits",
        "dockerLabels", "startTimeout",
      ] :
      jsondecode(output.container_definitions)[0][field] == jsondecode(var.container_definitions)[0][field]
    ])
    error_message = "fields the module does not rewrite must be unchanged"
  }

  assert {
    condition     = jsondecode(output.container_definitions)[0].environment[0].name == "APP_ENV"
    error_message = "the original environment entries must survive the rewrite"
  }

  assert {
    condition     = jsondecode(output.container_definitions)[0].cpu == 512
    error_message = "the app container keeps its own CPU units; the sidecar weight is never copied to it"
  }
}

run "ring_volume_per_container_env_and_pid_mode" {
  command = plan

  module {
    source = "./modules/sensor-ecs-sidecar"
  }

  variables {
    enable_observer       = false
    enable_ptrace         = false
    libc                  = { app = "glibc", other = "musl", static = "none" }
    app_containers        = ["app", "other", "static"]
    container_definitions = <<-JSON
    [
      {"name": "app", "image": "a", "environment": [{"name": "RUNTIME_SENSOR_SHM_PATH", "value": "/tmp/own.bin"}]},
      {"name": "other", "image": "b"},
      {"name": "static", "image": "c"}
    ]
    JSON
  }

  # Every instrumented app container mounts the ring volume read-write at the shared root.
  assert {
    condition = alltrue([
      for c in jsondecode(output.container_definitions) : (
        length([for m in c.mountPoints : m if m.sourceVolume == "neuralsec-sensor-ring" && m.containerPath == "/opt/neuralsec-sensor/ring" && m.readOnly == false]) == 1
      ) if contains(["app", "other", "static"], c.name)
    ])
    error_message = "app containers must mount neuralsec-sensor-ring read-write at /opt/neuralsec-sensor/ring"
  }

  # Each hooked container gets its own path; a customer value is replaced, never duplicated.
  assert {
    condition = (
      [for e in jsondecode(output.container_definitions)[0].environment : e.value if e.name == "RUNTIME_SENSOR_SHM_PATH"] == ["/opt/neuralsec-sensor/ring/app/ring.bin"]
      && [for e in jsondecode(output.container_definitions)[1].environment : e.value if e.name == "RUNTIME_SENSOR_SHM_PATH"] == ["/opt/neuralsec-sensor/ring/other/ring.bin"]
    )
    error_message = "hooked containers need a per-container RUNTIME_SENSOR_SHM_PATH"
  }

  assert {
    condition     = !contains([for e in try(jsondecode(output.container_definitions)[2].environment, []) : e.name], "RUNTIME_SENSOR_SHM_PATH")
    error_message = "a static image gets no ring path"
  }

  # The init container prepares the ring root; every app waits for it with COMPLETE.
  assert {
    condition = (
      contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].command, "--prepare-ring-dir")
      && [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].command[length([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].command) - 1] == "/opt/neuralsec-sensor/ring"
      && alltrue([for c in jsondecode(output.container_definitions) : (
        [for d in c.dependsOn : d.condition if d.containerName == "neuralsec-sensor-init"] == ["COMPLETE"]
      ) if contains(["app", "other", "static"], c.name)])
    )
    error_message = "the init container prepares the ring root and every app depends on it with COMPLETE"
  }

  # Hooks mean a drain role even with the observer off, and that needs the shared PID namespace.
  assert {
    condition = (
      contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].command, "--hook-ring")
      && !contains([for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].command, "--observe")
      && output.pid_mode == "task"
    )
    error_message = "the drain role needs the sidecar container and pidMode task"
  }

  assert {
    condition     = length([for m in [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor"][0].mountPoints : m if m.sourceVolume == "neuralsec-sensor-ring" && m.readOnly == false]) == 1
    error_message = "the sidecar mounts the ring volume read-write"
  }

  assert {
    condition     = length([for m in [for c in jsondecode(output.container_definitions) : c if c.name == "neuralsec-sensor-init"][0].mountPoints : m if m.sourceVolume == "neuralsec-sensor-ring" && m.readOnly == false]) == 1
    error_message = "the init container mounts the ring volume read-write"
  }
}
