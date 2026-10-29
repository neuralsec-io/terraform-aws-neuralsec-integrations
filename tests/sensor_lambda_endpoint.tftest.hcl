# sensor-lambda endpoint input: the endpoint is required, must be https, and is
# present in the environment of every enable path (wrapper, preload, egress
# proxy).

run "endpoint_must_be_https" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "http://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "zip"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  expect_failures = [var.endpoint]
}

run "endpoint_present_in_wrapper_environment" {
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
    condition     = output.environment["RUNTIME_SENSOR_ENDPOINT"] == "https://ingest.example.com"
    error_message = "wrapper mode must report the configured endpoint"
  }
  assert {
    condition     = output.environment["AWS_LAMBDA_EXEC_WRAPPER"] == "/opt/bin/sensor-wrapper"
    error_message = "wrapper mode must still install the sensor wrapper"
  }
}

run "endpoint_present_in_preload_environment" {
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
    runtime      = "provided.al2023"
  }

  assert {
    condition     = output.environment["RUNTIME_SENSOR_ENDPOINT"] == "https://ingest.example.com"
    error_message = "preload mode must report the configured endpoint"
  }
  assert {
    condition     = output.environment["LD_PRELOAD"] == "/opt/lib/libsensor_hook.so"
    error_message = "preload mode must still install the hook"
  }
}

run "endpoint_present_with_egress_proxy" {
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
    condition     = output.environment["RUNTIME_SENSOR_ENDPOINT"] == "https://ingest.example.com"
    error_message = "the egress proxy path must keep the configured endpoint"
  }
  assert {
    condition     = output.environment["HTTPS_PROXY"] == "http://127.0.0.1:9555"
    error_message = "the egress proxy path must still point HTTPS_PROXY at the sensor proxy"
  }
}

run "endpoint_in_container_image_instructions" {
  command = plan

  module {
    source = "./modules/sensor-lambda"
  }

  variables {
    endpoint     = "https://ingest.example.com"
    environment  = {}
    layers       = []
    architecture = "x86_64"
    package_type = "image"
    region       = "us-east-1"
    runtime      = "python3.12"
  }

  assert {
    condition     = strcontains(output.image_instructions, "ENV RUNTIME_SENSOR_ENDPOINT=https://ingest.example.com")
    error_message = "container images get the endpoint as a Dockerfile ENV line"
  }
}
