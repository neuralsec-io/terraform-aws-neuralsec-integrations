output "environment" {
  description = "The function's desired environment variables, to pass to aws_lambda_function. Unchanged for a container image."
  value       = local.is_image ? local.env : local.final_env

  precondition {
    condition     = local.mode != "preload" || length(local.restore_dropped) == 0
    error_message = format("converting to preload mode would drop wrappers from RUNTIME_SENSOR_CHAIN_WRAPPER: %s. Keep mode = \"wrapper\" or remove them first.", join(", ", local.restore_dropped))
  }

  precondition {
    condition     = !var.egress_proxy || length(local.foreign_proxy) == 0
    error_message = format("the function already defines proxy variables the sensor will not chain to: %s", join(", ", local.foreign_proxy))
  }

  precondition {
    condition     = local.is_image || local.env_size <= 4096
    error_message = format("the resulting environment is %d bytes, over Lambda's 4096-byte limit", local.env_size)
  }
}

output "layers" {
  description = "The function's desired layer ARNs, to pass to aws_lambda_function. Unchanged for a container image."
  value       = local.desired_layers

  precondition {
    condition     = local.is_image || local.region_layers != null
    error_message = format("region %q is not covered by layers.json; the sensor layer is not published there yet", var.region)
  }

  precondition {
    condition     = local.is_image || local.had_sensor || length(var.layers) < 5
    error_message = "adding the sensor layer would exceed Lambda's 5-layer limit"
  }
}

output "warnings" {
  description = "Conditions the caller should surface: a provided.* runtime, the egress proxy's HTTPS-path warning, or an image ENV override."
  value       = local.warnings
}

output "image_instructions" {
  description = "For package_type = Image only: the Dockerfile lines replacing the layer. Null for a zip function."
  value       = local.is_image ? local.image_instructions : null
}
