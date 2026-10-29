# Rewrites an ECS task definition to add the Neuralsec sensor components:
#
#   * `neuralsec-sensor-init`: non-essential, copies both hook builds into the
#     shared volume and exits. App containers depend on it with COMPLETE, which
#     proceeds whatever its exit code, so a failed copy can never keep the app
#     from starting (fail-open).
#   * `neuralsec-sensor`: non-essential observer and/or opt-in tracer. Nothing
#     depends on it.
#
# The sidecar used to be a single container with a HEALTHY dependency. That
# deadlocks fail-open: a failed install writes no readiness marker, the app
# waits forever, and the task never starts.
#
# Everything else in the customer's definitions is preserved at the JSON value
# level: fields we do not touch are copied unchanged, and absent fields stay
# absent.
#
# CPU weight: ECS turns each container's `cpu` into a CPU share weight. Both
# sensor containers request the minimum (2). An app container without a `cpu`
# value therefore gets the same minimum weight as the sidecar, and the two
# compete for the task's vCPU on equal terms. Set `cpu` explicitly on every
# instrumented app container (task CPU minus 2 per sensor container) so the app
# keeps the vCPU and the sidecar only runs on what is left. The module never
# changes a customer container's `cpu`.

locals {
  init_name     = "neuralsec-sensor-init"
  observer_name = "neuralsec-sensor"
  hook_root     = "/opt/neuralsec-sensor/lib"
  hook_file     = "libsensor_hook.so"

  definitions      = jsondecode(var.container_definitions)
  observer_enabled = var.enable_observer || var.enable_ptrace

  volume_mount = {
    sourceVolume  = "neuralsec-sensor-lib"
    containerPath = local.hook_root
  }

  init_container = {
    name      = local.init_name
    image     = var.sidecar_image
    essential = false
    # Minimum container CPU units: ECS turns `cpu` into CPU shares, so 2 gives
    # the sidecar the lowest weight against the app container and it only runs
    # on CPU the app is not using.
    cpu     = 2
    command = ["--install-lib", local.hook_root]
    mountPoints = [
      merge(local.volume_mount, { readOnly = false }),
    ]
  }

  observer_container = merge(
    {
      name      = local.observer_name
      image     = var.sidecar_image
      essential = false
      # Same minimum CPU weight as the init container: the app always wins.
      cpu = 2
      command = concat(
        var.enable_observer ? ["--observe"] : [],
        var.enable_ptrace ? ["--ptrace"] : [],
      )
      environment = [
        { name = "RUNTIME_SENSOR_ENDPOINT", value = var.endpoint },
      ]
      mountPoints = [
        merge(local.volume_mount, { readOnly = false }),
      ]
    },
    # SYS_PTRACE goes on the observer only, and only when the tracer is on.
    var.enable_ptrace ? {
      linuxParameters = {
        capabilities = {
          add = ["SYS_PTRACE"]
        }
      }
    } : {},
  )

  # Encoded as text for the same reason as the app containers: the init and
  # observer objects have different attribute sets.
  appended = concat(
    [jsonencode(local.init_container)],
    local.observer_enabled ? [jsonencode(local.observer_container)] : [],
  )

  # Per-container hook path, or null when the image is static / libc unknown.
  hook_paths = {
    for container in local.definitions : try(container.name, "") => (
      lookup(var.libc, try(container.name, ""), "none") == "none"
      ? null
      : "${local.hook_root}/${lookup(var.libc, try(container.name, ""), "none")}/${local.hook_file}"
    )
  }

  # Existing LD_PRELOAD entries are preserved and the hook is appended with ":".
  environments = {
    for container in local.definitions : try(container.name, "") => (
      local.hook_paths[try(container.name, "")] == null
      ? try(container.environment, [])
      : (
        contains([for entry in try(container.environment, []) : try(entry.name, "")], "LD_PRELOAD")
        ? [
          for entry in try(container.environment, []) : try(entry.name, "") == "LD_PRELOAD" ? merge(
            entry,
            { value = "${try(entry.value, "")}:${local.hook_paths[try(container.name, "")]}" },
          ) : entry
        ]
        : concat(
          try(container.environment, []),
          [{ name = "LD_PRELOAD", value = local.hook_paths[try(container.name, "")] }],
        )
      )
    )
  }

  # Encoded per container: Terraform cannot unify the original object type
  # with the merged one, so each element crosses the boundary as JSON text.
  encoded_containers = [
    for container in local.definitions : (
      contains(var.app_containers, try(container.name, "")) ? jsonencode(
        merge(
          container,
          {
            dependsOn = concat(
              try(container.dependsOn, []),
              [{ containerName = local.init_name, condition = "COMPLETE" }],
            )
            mountPoints = concat(
              try(container.mountPoints, []),
              [merge(local.volume_mount, { readOnly = true })],
            )
          },
          # Only present when this container gets a hook: a static image keeps
          # its environment exactly as it was.
          jsondecode(
            local.hook_paths[try(container.name, "")] == null
            ? "{}"
            : jsonencode({ environment = local.environments[try(container.name, "")] })
          ),
        )
      ) : jsonencode(container)
    )
  ]
}
