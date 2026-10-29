# sensor-eks module: the chart values rendered from the inputs, with the
# caller's `values` merged last. Plan only against a mocked Helm provider: no
# cluster, no credentials.

mock_provider "helm" {}

variables {
  endpoint     = "https://sensor.example.com"
  cluster_name = "example-cluster"
  image_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

run "renders_inputs_into_values" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).endpoint == "https://sensor.example.com"
    error_message = "the rendered values must carry the configured endpoint"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).clusterName == "example-cluster"
    error_message = "the rendered values must carry clusterName"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).image.digest == "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "the rendered values must carry image.digest"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).securityContext.privileged == false
    error_message = "privileged must default to false in the rendered values"
  }

  assert {
    condition     = output.namespace == "neuralsec" && output.release_name == "neuralsec-sensor" && output.chart_version == "0.1.0"
    error_message = "the outputs must expose the namespace, release name and chart version"
  }
}

run "release_installs_the_chart_from_the_oci_repository" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  assert {
    condition = (
      helm_release.sensor.name == "neuralsec-sensor"
      && helm_release.sensor.namespace == "neuralsec"
      && helm_release.sensor.create_namespace == true
      && helm_release.sensor.chart == "neuralsec-sensor"
      && helm_release.sensor.repository == "oci://public.ecr.aws/neuralsec/charts"
      && helm_release.sensor.version == "0.1.0"
    )
    error_message = "the release must install the chart from the OCI repository at the pinned chart version"
  }
}

run "endpoint_must_be_https" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  variables {
    endpoint = "http://sensor.example.com"
  }

  expect_failures = [var.endpoint]
}

run "image_digest_must_be_a_sha256_digest" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  variables {
    image_digest = "sha256:not-a-digest"
  }

  expect_failures = [var.image_digest]
}

run "values_override_the_rendered_defaults" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  variables {
    values = {
      endpoint        = "https://override.example.com"
      securityContext = { privileged = true }
      extraEnv        = [{ name = "LOG_LEVEL", value = "debug" }]
    }
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).endpoint == "https://override.example.com"
    error_message = "var.values must be merged last: its endpoint wins over the input"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).securityContext.privileged == true
    error_message = "var.values must override securityContext.privileged"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).extraEnv[0].name == "LOG_LEVEL"
    error_message = "keys only present in var.values must reach the rendered values"
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).image.digest == "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "keys var.values does not touch must keep their rendered value"
  }
}

run "privileged_input_reaches_the_values" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  variables {
    privileged = true
  }

  assert {
    condition     = yamldecode(helm_release.sensor.values[0]).securityContext.privileged == true
    error_message = "the privileged input must render into securityContext.privileged"
  }
}

run "namespace_is_configurable" {
  command = plan

  module {
    source = "./modules/sensor-eks"
  }

  variables {
    namespace        = "observability"
    create_namespace = false
  }

  assert {
    condition = (
      helm_release.sensor.namespace == "observability"
      && helm_release.sensor.create_namespace == false
      && output.namespace == "observability"
    )
    error_message = "the namespace and create_namespace inputs must reach the release"
  }
}
