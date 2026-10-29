# Shared enable vectors: the behaviour the Neuralsec sensor enable path must
# reproduce on every case. The vectors are shared with the enable CLI, so the
# expected values are fixed; do not edit them by hand.

run "enable_fresh_managed_runtime" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_fresh_managed_runtime: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_fresh_managed_runtime: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_fresh_managed_runtime: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_fresh_managed_runtime: image_instructions must be null for a zip function"
  }
}

run "enable_keeps_empty_preload" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "LD_PRELOAD" = "" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "LD_PRELOAD" = "" })
    error_message = "enable_keeps_empty_preload: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_keeps_empty_preload: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_keeps_empty_preload: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_keeps_empty_preload: image_instructions must be null for a zip function"
  }
}

run "enable_idempotent" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" }
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_idempotent: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_idempotent: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_idempotent: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_idempotent: image_instructions must be null for a zip function"
  }
}

run "enable_zip_mode_b_without_layer_adds_layer" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_zip_mode_b_without_layer_adds_layer: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_zip_mode_b_without_layer_adds_layer: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_zip_mode_b_without_layer_adds_layer: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_zip_mode_b_without_layer_adds_layer: image_instructions must be null for a zip function"
  }
}

run "enable_migrates_existing_wrapper" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/otel-instrument", "RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER" = "/opt/otel-instrument" })
    error_message = "enable_migrates_existing_wrapper: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_migrates_existing_wrapper: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_migrates_existing_wrapper: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_migrates_existing_wrapper: image_instructions must be null for a zip function"
  }
}

run "enable_prepends_to_existing_chain" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/acme/wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/other/wrapper" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/acme/wrapper:/opt/other/wrapper", "RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER" = "/opt/acme/wrapper" })
    error_message = "enable_prepends_to_existing_chain: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_prepends_to_existing_chain: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_prepends_to_existing_chain: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_prepends_to_existing_chain: image_instructions must be null for a zip function"
  }
}

run "enable_chain_dedupes_existing_entry" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/acme/wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/other/wrapper:/opt/acme/wrapper" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/acme/wrapper:/opt/other/wrapper", "RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER" = "/opt/acme/wrapper" })
    error_message = "enable_chain_dedupes_existing_entry: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_chain_dedupes_existing_entry: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_chain_dedupes_existing_entry: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_chain_dedupes_existing_entry: image_instructions must be null for a zip function"
  }
}

run "enable_replaces_old_layer_version" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:4", "arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:3", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-b:2"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_replaces_old_layer_version: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:4", "arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-b:2"])
    error_message = "enable_replaces_old_layer_version: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_replaces_old_layer_version: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_replaces_old_layer_version: image_instructions must be null for a zip function"
  }
}

run "enable_layer_limit" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:4", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-b:2", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-c:1", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-d:1", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-e:1"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  expect_failures = [output.layers]
}

run "enable_keeps_duplicate_layers" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_keeps_duplicate_layers: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1", "arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_keeps_duplicate_layers: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_keeps_duplicate_layers: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_keeps_duplicate_layers: image_instructions must be null for a zip function"
  }
}

run "enable_env_too_large" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "PAD" = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  expect_failures = [output.environment]
}

run "enable_env_too_large_non_ascii" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "PAD" = "éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  expect_failures = [output.environment]
}

run "enable_provided_runtime_preload" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "LD_PRELOAD" = "/opt/customer/lib.so" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "provided.al2023"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "LD_PRELOAD" = "/opt/lib/libsensor_hook.so:/opt/customer/lib.so" })
    error_message = "enable_provided_runtime_preload: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_provided_runtime_preload: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["provided.* runtime: Go and statically linked binaries are covered by Mode A only; the hook is not loaded into them."])
    error_message = "enable_provided_runtime_preload: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_provided_runtime_preload: image_instructions must be null for a zip function"
  }
}

run "enable_preload_musl" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    mode         = "preload"
    libc         = "musl"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "LD_PRELOAD" = "/opt/lib/musl/libsensor_hook.so" })
    error_message = "enable_preload_musl: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_preload_musl: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_preload_musl: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_preload_musl: image_instructions must be null for a zip function"
  }
}

run "enable_preload_converts_wrapper" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "RUNTIME_SENSOR_CHAIN_WRAPPER" = "/opt/otel-instrument", "RUNTIME_SENSOR_MIGRATED_EXEC_WRAPPER" = "/opt/otel-instrument" }
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    mode         = "preload"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument", "LD_PRELOAD" = "/opt/lib/libsensor_hook.so" })
    error_message = "enable_preload_converts_wrapper: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_preload_converts_wrapper: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_preload_converts_wrapper: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_preload_converts_wrapper: image_instructions must be null for a zip function"
  }
}

run "enable_container_image" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument" }
    layers       = []
    architecture = "x86_64"
    package_type = "image"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument" })
    error_message = "enable_container_image: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode([])
    error_message = "enable_container_image: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["the function configuration sets AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument, which overrides the image ENV line; remove it so the baked wrapper takes effect"])
    error_message = "enable_container_image: warnings differ from the shared vector"
  }
  assert {
    condition = output.image_instructions == chomp(<<-EOT
COPY --from=<registry>/neuralsec-sensor-lambda:<version> /opt /opt
ENV RUNTIME_SENSOR_ENDPOINT=https://ingest.example.com
ENV AWS_LAMBDA_EXEC_WRAPPER=/opt/bin/sensor-wrapper
ENV RUNTIME_SENSOR_CHAIN_WRAPPER=/opt/otel-instrument
# WARNING: the function configuration sets AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument, which overrides the image ENV line; remove it so the baked wrapper takes effect
EOT
    )
    error_message = "enable_container_image: image_instructions differ from the shared vector"
  }
}

run "enable_arm64_layer" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "arm64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "nodejs22.x"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_arm64_layer: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-arm64:7"])
    error_message = "enable_arm64_layer: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_arm64_layer: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_arm64_layer: image_instructions must be null for a zip function"
  }
}

run "enable_unsupported_region" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "ap-south-1"
    runtime      = "python3.12"
  }

  expect_failures = [output.layers]
}

run "enable_egress_proxy_fresh" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_fresh: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_fresh: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_fresh: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_fresh: image_instructions must be null for a zip function"
  }
}

run "enable_egress_proxy_custom_port" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "RUNTIME_SENSOR_PROXY_PORT" = "9600" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9600", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_PROXY_PORT" = "9600", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9600", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_custom_port: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_custom_port: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_custom_port: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_custom_port: image_instructions must be null for a zip function"
  }
}

run "enable_egress_proxy_merges_no_proxy" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "NO_PROXY" = "127.0.0.1,internal.example,10.0.0.0/8" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "127.0.0.1,internal.example,10.0.0.0/8,localhost,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_merges_no_proxy: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_merges_no_proxy: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_merges_no_proxy: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_merges_no_proxy: image_instructions must be null for a zip function"
  }
}

run "enable_egress_proxy_refuses_existing" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "HTTPS_PROXY" = "http://corp.example:3128" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  expect_failures = [output.environment]
}

run "enable_egress_proxy_refuses_all_proxy" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "ALL_PROXY" = "socks5://corp.example:1080" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  expect_failures = [output.environment]
}

run "enable_egress_proxy_idempotent" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" }
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_idempotent: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_idempotent: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_idempotent: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_idempotent: image_instructions must be null for a zip function"
  }
}

run "enable_egress_proxy_warns" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_warns: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_warns: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_warns: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_warns: image_instructions must be null for a zip function"
  }
}

run "enable_egress_proxy_env_too_large" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "PAD" = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" }
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  expect_failures = [output.environment]
}

run "enable_egress_proxy_container_image" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument" }
    layers       = []
    architecture = "x86_64"
    package_type = "image"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/otel-instrument" })
    error_message = "enable_egress_proxy_container_image: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode([])
    error_message = "enable_egress_proxy_container_image: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it.", "the function configuration sets AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument, which overrides the image ENV line; remove it so the baked wrapper takes effect"])
    error_message = "enable_egress_proxy_container_image: warnings differ from the shared vector"
  }
  assert {
    condition = output.image_instructions == chomp(<<-EOT
COPY --from=<registry>/neuralsec-sensor-lambda:<version> /opt /opt
ENV RUNTIME_SENSOR_ENDPOINT=https://ingest.example.com
ENV AWS_LAMBDA_EXEC_WRAPPER=/opt/bin/sensor-wrapper
ENV RUNTIME_SENSOR_CHAIN_WRAPPER=/opt/otel-instrument
ENV HTTPS_PROXY=http://127.0.0.1:9555
ENV https_proxy=http://127.0.0.1:9555
ENV RUNTIME_SENSOR_PROXY=1
ENV NO_PROXY=localhost,127.0.0.1,::1,169.254.0.0/16
ENV no_proxy=localhost,127.0.0.1,::1,169.254.0.0/16
# WARNING: egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it.
# WARNING: the function configuration sets AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument, which overrides the image ENV line; remove it so the baked wrapper takes effect
EOT
    )
    error_message = "enable_egress_proxy_container_image: image_instructions differ from the shared vector"
  }
}

run "enable_egress_proxy_extends_added_marker" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost", "RUNTIME_SENSOR_PROXY" = "1", "https_proxy" = "http://127.0.0.1:9555" }
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
    egress_proxy = true
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper", "HTTPS_PROXY" = "http://127.0.0.1:9555", "NO_PROXY" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_NO_PROXY_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "RUNTIME_SENSOR_PROXY" = "1", "RUNTIME_SENSOR_no_proxy_ADDED" = "localhost,127.0.0.1,::1,169.254.0.0/16", "https_proxy" = "http://127.0.0.1:9555", "no_proxy" = "localhost,127.0.0.1,::1,169.254.0.0/16" })
    error_message = "enable_egress_proxy_extends_added_marker: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_egress_proxy_extends_added_marker: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode(["egress proxy: the sensor extension is now on this function's HTTPS path; if the extension fails, outbound HTTPS from the function fails until Lambda replaces the sandbox. Plain HTTP is not proxied and clients that ignore proxy variables bypass it."])
    error_message = "enable_egress_proxy_extends_added_marker: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_egress_proxy_extends_added_marker: image_instructions must be null for a zip function"
  }
}

run "enable_snapstart_warns" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_snapstart_warns: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7"])
    error_message = "enable_snapstart_warns: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_snapstart_warns: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_snapstart_warns: image_instructions must be null for a zip function"
  }
}

run "enable_replaces_all_sensor_layers" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = ["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:3", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1", "arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-arm64:4"]
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "enable_replaces_all_sensor_layers: environment differs from the shared vector"
  }
  assert {
    condition     = jsonencode(output.layers) == jsonencode(["arn:aws:lambda:us-east-1:123456789012:layer:neuralsec-sensor-x86_64:7", "arn:aws:lambda:us-east-1:123456789012:layer:vendor-a:1"])
    error_message = "enable_replaces_all_sensor_layers: layers differ from the shared vector"
  }
  assert {
    condition     = jsonencode(output.warnings) == jsonencode([])
    error_message = "enable_replaces_all_sensor_layers: warnings differ from the shared vector"
  }
  assert {
    condition     = output.image_instructions == null
    error_message = "enable_replaces_all_sensor_layers: image_instructions must be null for a zip function"
  }
}
