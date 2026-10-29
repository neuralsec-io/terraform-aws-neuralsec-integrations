# Hand-written egress proxy coverage. The vectors file covers the shared enable
# vectors, including every enable_egress_proxy_* case; these runs pin the
# default (off) and the declarative reversal that replaces the CLI's disable
# command.

run "egress_proxy_default_false_changes_nothing" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    runtime      = "python3.12"
    package_type = "zip"
    region       = "us-east-1"
  }

  assert {
    condition     = length(output.environment) == 2
    error_message = "egress_proxy defaults to false: only the wrapper and the endpoint may be added"
  }
  assert {
    condition     = !contains(keys(output.environment), "RUNTIME_SENSOR_PROXY")
    error_message = "egress_proxy defaults to false: the sensor proxy marker must not be set"
  }
  assert {
    condition     = !contains(keys(output.environment), "HTTPS_PROXY")
    error_message = "egress_proxy defaults to false: HTTPS_PROXY must not be set"
  }
  assert {
    condition     = length(output.warnings) == 0
    error_message = "egress_proxy defaults to false: no warning may be emitted"
  }
}

run "egress_proxy_false_leaves_customer_proxy_vars_alone" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint = "https://ingest.example.com"
    environment = {
      "HTTPS_PROXY"               = "http://corp.example:3128"
      "RUNTIME_SENSOR_PROXY_PORT" = "9600"
    }
    layers       = []
    architecture = "x86_64"
    runtime      = "python3.12"
    package_type = "zip"
    region       = "us-east-1"
    egress_proxy = false
  }

  assert {
    condition     = output.environment["HTTPS_PROXY"] == "http://corp.example:3128"
    error_message = "a customer HTTPS_PROXY must pass through untouched when egress_proxy is false"
  }
  assert {
    condition     = !contains(keys(output.environment), "RUNTIME_SENSOR_PROXY")
    error_message = "egress_proxy = false must not mark the sensor as the proxy owner"
  }
  assert {
    condition     = length(output.warnings) == 0
    error_message = "egress_proxy = false must not warn"
  }
}

run "egress_proxy_enabled_baseline" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "NO_PROXY" = "corp.example" }
    layers       = []
    architecture = "x86_64"
    runtime      = "python3.12"
    package_type = "zip"
    region       = "us-east-1"
    egress_proxy = true
  }

  assert {
    condition     = output.environment["RUNTIME_SENSOR_PROXY"] == "1"
    error_message = "egress_proxy = true must set the sensor proxy marker"
  }
  assert {
    condition     = output.environment["HTTPS_PROXY"] == "http://127.0.0.1:9555"
    error_message = "egress_proxy = true must point HTTPS_PROXY at the default port"
  }
  assert {
    condition     = output.environment["NO_PROXY"] == "corp.example,localhost,127.0.0.1,::1,169.254.0.0/16"
    error_message = "egress_proxy = true must keep the customer NO_PROXY entries and append the sensor ones"
  }
}

run "egress_proxy_disabled_baseline" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "NO_PROXY" = "corp.example" }
    layers       = []
    architecture = "x86_64"
    runtime      = "python3.12"
    package_type = "zip"
    region       = "us-east-1"
    egress_proxy = false
  }

  assert {
    condition     = output.environment["NO_PROXY"] == "corp.example"
    error_message = "the pre-feature environment keeps the customer NO_PROXY"
  }
}

run "egress_proxy_disable_reverses_exactly" {
  # The module is declarative: the caller flips egress_proxy back to false and
  # the module recomputes from the customer's own map, so the proxy variables are
  # gone by construction and the original environment comes back. No state is
  # carried over from egress_proxy_enabled_baseline.
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = { "NO_PROXY" = "corp.example" }
    layers       = []
    architecture = "x86_64"
    runtime      = "python3.12"
    package_type = "zip"
    region       = "us-east-1"
  }

  assert {
    condition     = output.environment["NO_PROXY"] == "corp.example"
    error_message = "removing egress_proxy must restore the customer NO_PROXY exactly"
  }
  assert {
    condition     = !contains(keys(output.environment), "HTTPS_PROXY") && !contains(keys(output.environment), "RUNTIME_SENSOR_PROXY")
    error_message = "removing egress_proxy must remove every proxy variable"
  }
  assert {
    condition     = !contains(keys(output.environment), "RUNTIME_SENSOR_NO_PROXY_ADDED")
    error_message = "removing egress_proxy must not leave the added-entry marker behind"
  }
  assert {
    # The full environment, not just its keys: the customer map plus the one
    # wrapper and the endpoint the module adds. OpenTofu 1.13.2 cannot read a
    # previous run's outputs, so the wrapper (layers.json) is spelled out here;
    # the shared vectors cover the same value in every release.
    condition     = jsonencode(output.environment) == jsonencode({ "RUNTIME_SENSOR_ENDPOINT" = "https://ingest.example.com", "NO_PROXY" = "corp.example", "AWS_LAMBDA_EXEC_WRAPPER" = "/opt/bin/sensor-wrapper" })
    error_message = "the environment with egress_proxy removed must equal the pre-feature environment byte for byte: the wrapper, the endpoint and the customer NO_PROXY only"
  }
  assert {
    condition     = length(output.environment) == 3 && contains(keys(output.environment), "NO_PROXY") && contains(keys(output.environment), "AWS_LAMBDA_EXEC_WRAPPER") && contains(keys(output.environment), "RUNTIME_SENSOR_ENDPOINT")
    error_message = "the environment with egress_proxy removed must equal the pre-feature environment: the wrapper, the endpoint and the customer NO_PROXY only"
  }
}
