# Rewrites an ECS task definition to add the Neuralsec sensor components:
#
#   * `neuralsec-sensor-init`: non-essential, copies both hook builds into the
#     shared volume and exits. App containers depend on it with COMPLETE, which
#     proceeds whatever its exit code, so a failed copy can never keep the app
#     from starting (fail-open).
#   * `neuralsec-sensor`: non-essential observer and/or opt-in tracer. Nothing
#     depends on it.
#
# Hook delivery needs the ingest endpoint: the `neuralsec-sensor` container
# drains the apps' hook rings (`--hook-ring`) only when it has
# `RUNTIME_SENSOR_ENDPOINT` in its environment. This module sets it from the
# required `endpoint` variable. Without the endpoint the sidecar reports one
# `SensorHealth` line on stdout naming the missing variable and the rings stay
# unread.
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
  # Shared ring volume. The init container makes the root directory (root-owned,
  # 1777 like /tmp) and nothing else: each hooked container gets its own
  # subdirectory <ring_root>/<container>/ring.bin, created by the hook under the
  # app's own uid, so containers with different uids never share a ring. The
  # sidecar (root) only reads them.
  ring_root = "/opt/neuralsec-sensor/ring"

  definitions      = jsondecode(var.container_definitions)
  observer_enabled = var.enable_observer || var.enable_ptrace

  volume_mount = {
    sourceVolume  = "neuralsec-sensor-lib"
    containerPath = local.hook_root
  }

  ring_mount = {
    sourceVolume  = "neuralsec-sensor-ring"
    containerPath = local.ring_root
    readOnly      = false
  }

  # The sidecar drains the rings, so it runs (and the task shares one PID
  # namespace for the lane-owner liveness check) whenever at least one container
  # gets a hook.
  drain_enabled  = anytrue([for path in values(local.hook_paths) : path != null])
  sidecar_needed = local.observer_enabled || local.drain_enabled

  init_container = {
    name      = local.init_name
    image     = var.sidecar_image
    essential = false
    # Minimum container CPU units: ECS turns `cpu` into CPU shares, so 2 gives
    # the sidecar the lowest weight against the app container and it only runs
    # on CPU the app is not using.
    cpu     = 2
    command = ["--install-lib", local.hook_root, "--prepare-ring-dir", local.ring_root]
    mountPoints = [
      merge(local.volume_mount, { readOnly = false }),
      local.ring_mount,
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
        local.drain_enabled ? ["--hook-ring", local.ring_root] : [],
      )
      environment = [
        { name = "RUNTIME_SENSOR_ENDPOINT", value = var.endpoint },
      ]
      mountPoints = [
        merge(local.volume_mount, { readOnly = false }),
        local.ring_mount,
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
    local.sidecar_needed ? [jsonencode(local.observer_container)] : [],
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
  preload_environments = {
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

  # Hooked containers also get their own ring path (one subdirectory per
  # container). A customer value for the same variable is replaced, never
  # duplicated, so the hook always writes where the sidecar drains.
  environments = {
    for container in local.definitions : try(container.name, "") => concat(
      [for entry in local.preload_environments[try(container.name, "")] : entry if try(entry.name, "") != "RUNTIME_SENSOR_SHM_PATH"],
      [
        for hooked in [local.hook_paths[try(container.name, "")]] :
        { name = "RUNTIME_SENSOR_SHM_PATH", value = "${local.ring_root}/${try(container.name, "")}/ring.bin" }
        if hooked != null
      ],
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
              [merge(local.volume_mount, { readOnly = true }), local.ring_mount],
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
