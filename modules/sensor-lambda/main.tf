# Neuralsec sensor Terraform module: the Lambda enable rule as a pure
# computation.
#
# The module creates no resources and calls no provider. It takes the parts of a
# function configuration the planner needs and returns the desired environment
# and layers for the caller's own `aws_lambda_function`, so Terraform stays the
# single owner of the configuration. Layer ARNs, the wrapper and the hook paths
# come from `layers.json`, the file the enable CLI embeds, so the two cannot
# diverge. The shared vectors in `tests/` prove that on every case.

locals {
  layers_data = jsondecode(file("${path.module}/layers.json"))

  is_image = lower(var.package_type) == "image"
  runtime  = var.runtime == null ? "" : var.runtime
  provided = startswith(local.runtime, "provided.")
  mode     = var.mode != null ? var.mode : (local.provided ? "preload" : "wrapper")

  wrapper      = local.layers_data.wrapper
  hooks        = local.layers_data.hooks
  sensor_hooks = [local.hooks.glibc, local.hooks.musl]
  hook         = local.hooks[var.libc]

  # Null in a region the table does not cover; the `layers` precondition
  # reports that instead of failing on the lookup.
  region_layers = try(local.layers_data.regions[var.region], null)
  sensor_arn    = try(local.region_layers[var.architecture], null)

  # A sensor layer is one whose name matches the table, whatever the region,
  # version or architecture, so an older or wrong-arch entry is replaced too.
  # Keyed by index: `var.layers` may repeat an ARN, and the CLI keeps duplicates.
  sensor_markers = [
    for name in [local.layers_data.layer_names.x86_64, local.layers_data.layer_names.arm64] :
    ":layer:${name}:"
  ]
  layer_is_sensor = {
    for i, arn in var.layers : i => anytrue([for marker in local.sensor_markers : strcontains(arn, marker)])
  }
  had_sensor   = anytrue([for i, arn in var.layers : local.layer_is_sensor[i]])
  first_sensor = local.had_sensor ? index([for i, arn in var.layers : local.layer_is_sensor[i]], true) : -1

  # One sensor layer, at the position of the first one, in the function's
  # region and architecture; every other layer keeps its place and order.
  replaced_layers = [
    for i, arn in var.layers :
    local.layer_is_sensor[i] ? (i == local.first_sensor ? local.sensor_arn : null) : arn
  ]
  desired_layers = local.is_image ? var.layers : (
    local.had_sensor
    ? [for arn in local.replaced_layers : arn if arn != null]
    : concat(var.layers, [local.sensor_arn])
  )

  env          = var.environment
  exec_wrapper = try(local.env["AWS_LAMBDA_EXEC_WRAPPER"], null)
  migrated     = try(local.env["RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER"], null)
  chain        = [for entry in split(":", try(local.env["RUNTIME_SENSOR_CHAIN_WRAPPER"], "")) : entry if entry != ""]

  # LD_PRELOAD without the sensor's hook: what preload mode starts from. Only
  # rewritten when a sensor entry was removed, so a customer value stays byte
  # for byte otherwise, including the empty string (CLI remove_sensor_preload).
  preload_parts         = split(":", try(local.env["LD_PRELOAD"], ""))
  preload_kept          = [for entry in local.preload_parts : entry if !contains(local.sensor_hooks, entry)]
  preload_changed       = length(local.preload_kept) != length(local.preload_parts)
  preload_value_removed = join(":", local.preload_kept)
  env_without_preload = local.preload_changed ? merge(
    { for key, value in local.env : key => value if key != "LD_PRELOAD" },
    local.preload_value_removed == "" ? {} : { LD_PRELOAD = local.preload_value_removed },
  ) : local.env

  # Wrapper mode: set the wrapper, or move the existing one
  # to the front of the chain and record it so `disable` can put it back.
  chain_input   = local.exec_wrapper != null ? local.exec_wrapper : ""
  wrapper_chain = distinct(concat([local.chain_input], [for entry in local.chain : entry if entry != local.chain_input && entry != local.wrapper]))
  wrapper_env = local.exec_wrapper == null ? merge(local.env_without_preload, {
    AWS_LAMBDA_EXEC_WRAPPER = local.wrapper
    }) : (
    local.exec_wrapper == local.wrapper ? local.env_without_preload : merge(local.env_without_preload, {
      AWS_LAMBDA_EXEC_WRAPPER              = local.wrapper
      RUNTIME_SENSOR_CHAIN_WRAPPER         = join(":", [for entry in local.wrapper_chain : entry if entry != ""])
      RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER = local.migrated != null ? local.migrated : local.exec_wrapper
  }))

  # Preload mode: converting from wrapper mode restores the migrated
  # wrapper first, as `disable` does. Entries beyond the migrated one cannot
  # survive Lambda's single wrapper slot, so they are refused, not dropped.
  restore_needed  = local.mode == "preload" && local.exec_wrapper == local.wrapper
  restore_dropped = local.restore_needed ? [for entry in local.chain : entry if entry != local.wrapper && entry != local.migrated] : []
  restored_env = local.restore_needed ? merge(
    { for key, value in local.env_without_preload : key => value if !contains(["AWS_LAMBDA_EXEC_WRAPPER", "RUNTIME_SENSOR_CHAIN_WRAPPER", "RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER"], key) },
    local.migrated != null ? { AWS_LAMBDA_EXEC_WRAPPER = local.migrated } : {},
    local.preload_value_removed == "" ? {} : { LD_PRELOAD = local.preload_value_removed },
  ) : local.env_without_preload

  preload_existing = try(local.restored_env["LD_PRELOAD"], "")
  preload_env = merge(local.restored_env, {
    LD_PRELOAD = local.preload_existing == "" ? local.hook : "${local.hook}:${local.preload_existing}"
  })

  mode_env = local.mode == "wrapper" ? local.wrapper_env : local.preload_env

  # Egress proxy (the CLI `--egress-proxy` flag). The tooling refuses to
  # chain to an upstream proxy, so any proxy variable it does not own is a
  # refusal (an own HTTPS_PROXY is what idempotent re-runs see).
  proxy_port        = try(local.mode_env["RUNTIME_SENSOR_PROXY_PORT"], "9555")
  proxy_url         = "http://127.0.0.1:${local.proxy_port}"
  sensor_owns_proxy = try(local.mode_env["RUNTIME_SENSOR_PROXY"], "") == "1"
  proxy_names       = ["HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"]
  foreign_proxy = [
    for name in local.proxy_names : name
    if lookup(local.mode_env, name, null) != null && !(upper(name) == "HTTPS_PROXY" && local.sensor_owns_proxy && lookup(local.mode_env, name, "") == local.proxy_url)
  ]

  no_proxy_base = ["localhost", "127.0.0.1", "::1", "169.254.0.0/16"]
  runtime_api   = trimspace(try(local.mode_env["AWS_LAMBDA_RUNTIME_API"], ""))
  runtime_api_host = local.runtime_api == "" ? null : (
    startswith(local.runtime_api, "[")
    ? try(regex("^\\[([^\\]]+)\\]", local.runtime_api)[0], null)
    : try(split(":", local.runtime_api)[0], null)
  )
  sensor_entries = (
    local.runtime_api_host == null ? local.no_proxy_base : (
      local.runtime_api_host == "" ? local.no_proxy_base : (
        contains(local.no_proxy_base, local.runtime_api_host)
        ? local.no_proxy_base
        : concat(local.no_proxy_base, [local.runtime_api_host])
      )
    )
  )

  # Merge the sensor's entries into NO_PROXY/no_proxy, keeping every customer
  # entry, and record what was added so `disable` can take exactly that back.
  np_upper_current  = try(local.mode_env["NO_PROXY"], "")
  np_upper_present  = [for entry in split(",", local.np_upper_current) : entry if entry != ""]
  np_upper_added    = distinct([for entry in local.sensor_entries : entry if !contains(local.np_upper_present, entry)])
  np_upper_recorded = [for entry in split(",", try(local.mode_env["RUNTIME_SENSOR_NO_PROXY_ADDED"], "")) : entry if entry != ""]
  np_upper_value    = local.np_upper_current == "" ? join(",", local.np_upper_added) : "${local.np_upper_current},${join(",", local.np_upper_added)}"
  no_proxy_upper = length(local.np_upper_added) == 0 ? {} : {
    NO_PROXY                      = local.np_upper_value
    RUNTIME_SENSOR_NO_PROXY_ADDED = join(",", concat(local.np_upper_recorded, [for entry in local.np_upper_added : entry if !contains(local.np_upper_recorded, entry)]))
  }

  np_lower_current  = try(local.mode_env["no_proxy"], "")
  np_lower_present  = [for entry in split(",", local.np_lower_current) : entry if entry != ""]
  np_lower_added    = distinct([for entry in local.sensor_entries : entry if !contains(local.np_lower_present, entry)])
  np_lower_recorded = [for entry in split(",", try(local.mode_env["RUNTIME_SENSOR_no_proxy_ADDED"], "")) : entry if entry != ""]
  np_lower_value    = local.np_lower_current == "" ? join(",", local.np_lower_added) : "${local.np_lower_current},${join(",", local.np_lower_added)}"
  no_proxy_lower = length(local.np_lower_added) == 0 ? {} : {
    no_proxy                      = local.np_lower_value
    RUNTIME_SENSOR_no_proxy_ADDED = join(",", concat(local.np_lower_recorded, [for entry in local.np_lower_added : entry if !contains(local.np_lower_recorded, entry)]))
  }

  proxy_env = merge(local.mode_env, {
    HTTPS_PROXY          = local.proxy_url
    https_proxy          = local.proxy_url
    RUNTIME_SENSOR_PROXY = "1"
  }, local.no_proxy_upper, local.no_proxy_lower)

  final_env = merge(var.egress_proxy ? local.proxy_env : local.mode_env, {
    RUNTIME_SENSOR_ENDPOINT = var.endpoint
  })

  # Lambda counts bytes and Terraform counts characters, so each string goes
  # through base64: 4 base64 characters carry 3 bytes, minus the padding
  # (the CLI environment size check). Same result for ASCII, correct elsewhere.
  env_size = sum([
    for key, value in local.final_env :
    (length(base64encode(key)) * 3 / 4 - length(regexall("=", base64encode(key))))
    + (length(base64encode(value)) * 3 / 4 - length(regexall("=", base64encode(value))))
  ])

  # Warnings, not failures. SnapStart is a CLI `--publish` concern and
  # has no input here.
  provided_warning = "provided.* runtime: Go and statically linked binaries are covered by Mode A only; the hook is not loaded into them."
  proxy_warning    = "egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."
  override_warning = local.exec_wrapper == null ? null : format("the function configuration sets AWS_LAMBDA_EXEC_WRAPPER=%s, which overrides the image ENV line; remove it so the baked wrapper takes effect", local.exec_wrapper)
  warnings = concat(
    local.provided ? [local.provided_warning] : [],
    var.egress_proxy ? [local.proxy_warning] : [],
    local.is_image && local.override_warning != null ? [local.override_warning] : [],
  )

  # Container images: layers do not apply and the environment output is
  # unchanged; the caller gets the Dockerfile lines instead, including the
  # endpoint the baked image must report to.
  image_existing_preload = [
    for entry in split(":", try(local.final_env["LD_PRELOAD"], "")) : entry
    if entry != "" && !contains(local.sensor_hooks, entry)
  ]
  image_preload = length(local.image_existing_preload) == 0 ? local.hook : "${local.hook}:${join(":", local.image_existing_preload)}"
  image_chain   = try(local.final_env["RUNTIME_SENSOR_CHAIN_WRAPPER"], "")
  image_lines = concat(
    ["COPY --from=<registry>/sensor-lambda:<version> /opt /opt"],
    ["ENV RUNTIME_SENSOR_ENDPOINT=${var.endpoint}"],
    local.mode == "wrapper"
    ? concat(
      ["ENV AWS_LAMBDA_EXEC_WRAPPER=${local.wrapper}"],
      local.image_chain == "" ? [] : ["ENV RUNTIME_SENSOR_CHAIN_WRAPPER=${local.image_chain}"],
    )
    : ["ENV LD_PRELOAD=${local.image_preload}"],
    var.egress_proxy ? [
      for name in ["HTTPS_PROXY", "https_proxy", "RUNTIME_SENSOR_PROXY", "NO_PROXY", "no_proxy"] :
      "ENV ${name}=${lookup(local.final_env, name, "")}" if contains(keys(local.final_env), name)
    ] : [],
    [for warning in local.warnings : "# WARNING: ${warning}"],
  )
  image_instructions = join("\n", local.image_lines)
}
