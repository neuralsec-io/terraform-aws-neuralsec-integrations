# sensor-ec2 module: the SSM document that installs the sensor on EC2 hosts and
# the association that runs it. Plan only against a mocked AWS provider: no
# credentials, no API calls.

mock_provider "aws" {}

variables {
  endpoint       = "https://sensor.example.com"
  sensor_version = "1.2.3"

  sha256 = {
    x86_64  = "1111111111111111111111111111111111111111111111111111111111111111"
    aarch64 = "2222222222222222222222222222222222222222222222222222222222222222"
  }
}

run "document_is_a_linux_command_document" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  assert {
    condition = (
      aws_ssm_document.sensor.document_type == "Command"
      && aws_ssm_document.sensor.document_format == "JSON"
      && jsondecode(aws_ssm_document.sensor.content).schemaVersion == "2.2"
    )
    error_message = "the installer must be a Command document with schemaVersion 2.2"
  }

  assert {
    condition     = jsondecode(aws_ssm_document.sensor.content).mainSteps[0].action == "aws:runShellScript"
    error_message = "the document must run the installer as a shell script"
  }

  assert {
    condition     = output.document_name == aws_ssm_document.sensor.name
    error_message = "the document_name output must expose the created document"
  }
}

run "document_pins_both_architectures_and_their_checksums" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  assert {
    condition = (
      strcontains(aws_ssm_document.sensor.content, "x86_64")
      && strcontains(aws_ssm_document.sensor.content, "1111111111111111111111111111111111111111111111111111111111111111")
      && strcontains(aws_ssm_document.sensor.content, "aarch64")
      && strcontains(aws_ssm_document.sensor.content, "2222222222222222222222222222222222222222222222222222222222222222")
    )
    error_message = "the script must map each architecture to its hex digest"
  }

  assert {
    condition = (
      strcontains(aws_ssm_document.sensor.content, "https://sensor.example.com")
      && strcontains(aws_ssm_document.sensor.content, "RUNTIME_SENSOR_ENDPOINT=https://sensor.example.com")
      && strcontains(aws_ssm_document.sensor.content, "RUNTIME_SENSOR_PLATFORM=ec2")
    )
    error_message = "the unit must report the configured endpoint and the ec2 platform"
  }
}

run "script_verifies_the_checksum_and_fails_closed" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "sha256sum")
    error_message = "the script must verify the downloaded artifact with sha256"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "checksum mismatch")
    error_message = "a digest mismatch must abort the install"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "neuralsec-sensor-linux-$arch.tar.gz")
    error_message = "the artifact URL must be selected from the detected architecture"
  }

  assert {
    condition = (
      strcontains(aws_ssm_document.sensor.content, "curl")
      && strcontains(aws_ssm_document.sensor.content, "wget")
    )
    error_message = "the download must work with either curl or wget"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "set -eu")
    error_message = "the script must run with set -eu"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "/usr/local/bin/neuralsec-sensor")
    error_message = "the binary must be installed at /usr/local/bin/neuralsec-sensor"
  }

  assert {
    condition     = strcontains(aws_ssm_document.sensor.content, "/etc/systemd/system/neuralsec-sensor.service")
    error_message = "the script must write the systemd unit"
  }
}

run "unit_carries_every_hardening_line" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  assert {
    condition = alltrue([
      for line in [
        "AmbientCapabilities=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE",
        "CapabilityBoundingSet=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE",
        "NoNewPrivileges=yes",
        "ProtectSystem=strict",
        "ProtectHome=yes",
        "PrivateTmp=yes",
        "ReadOnlyPaths=-/sys/kernel/btf -/sys/fs/cgroup -/sys/kernel/tracing",
        "MemoryMax=128M",
        "CPUQuota=20%",
        "Nice=19",
        "CPUSchedulingPolicy=idle",
        "IOSchedulingClass=idle",
        "Restart=on-failure",
        "RestartSec=10",
        "StandardOutput=null",
      ] : strcontains(aws_ssm_document.sensor.content, line)
    ])
    error_message = "the systemd unit must carry every hardening line"
  }

  assert {
    condition = (
      strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "systemctl daemon-reload")
      && strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "systemctl enable neuralsec-sensor.service")
      && strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "systemctl restart neuralsec-sensor.service")
      && strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "if [ \"$changed\" = 1 ]; then")
    )
    error_message = "the script must reload systemd, enable the unit and restart it when the binary or unit changed"
  }

  assert {
    condition = (
      strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "echo \"$expected_sha256\" > \"$stamp\"")
      && strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "[ \"$(cat \"$stamp\")\" = \"$expected_sha256\" ]")
      && !strcontains(jsondecode(aws_ssm_document.sensor.content).mainSteps[0].inputs.runCommand[0], "$binary\" | sha256sum -c")
    )
    error_message = "the skip check must compare the recorded archive digest, not the binary's own digest"
  }
}

run "association_targets_tagged_instances_and_reports_compliance" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  assert {
    condition = (
      aws_ssm_association.sensor.targets[0].key == "tag:neuralsec-sensor"
      && aws_ssm_association.sensor.targets[0].values[0] == "enabled"
    )
    error_message = "the default target must be instances tagged neuralsec-sensor=enabled"
  }

  assert {
    condition = (
      aws_ssm_association.sensor.schedule_expression == "rate(30 minutes)"
      && aws_ssm_association.sensor.compliance_severity == "MEDIUM"
    )
    error_message = "the association must run every 30 minutes and report MEDIUM compliance"
  }

  assert {
    condition     = output.document_name == "neuralsec-sensor"
    error_message = "the document_name output must expose the created document"
  }
}

run "custom_targets_and_schedule" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  variables {
    targets = [
      { key = "InstanceIds", values = ["i-0123456789abcdef0"] },
      { key = "tag:environment", values = ["prod"] },
    ]
    schedule = "rate(1 hour)"
  }

  assert {
    condition     = length(aws_ssm_association.sensor.targets) == 2
    error_message = "every configured target must reach the association"
  }

  assert {
    condition     = aws_ssm_association.sensor.schedule_expression == "rate(1 hour)"
    error_message = "the schedule input must override the default"
  }
}

run "uninstall_document_removes_everything_without_downloading" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  variables {
    uninstall = true
  }

  assert {
    condition = (
      !strcontains(aws_ssm_document.sensor.content, "curl")
      && !strcontains(aws_ssm_document.sensor.content, "wget")
      && !strcontains(aws_ssm_document.sensor.content, "tar -xzf")
    )
    error_message = "the uninstall document must not download anything"
  }

  assert {
    condition = (
      strcontains(aws_ssm_document.sensor.content, "systemctl disable --now neuralsec-sensor")
      && strcontains(aws_ssm_document.sensor.content, "rm -f /etc/systemd/system/neuralsec-sensor.service")
      && strcontains(aws_ssm_document.sensor.content, "rm -f /usr/local/bin/neuralsec-sensor")
    )
    error_message = "the uninstall document must stop, disable and remove the unit and the binary"
  }
}

run "sha256_must_be_64_hex_for_both_architectures" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  variables {
    sha256 = {
      x86_64  = "not-a-digest"
      aarch64 = "2222222222222222222222222222222222222222222222222222222222222222"
    }
  }

  expect_failures = [var.sha256]
}

run "sha256_must_name_both_architectures" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  variables {
    sha256 = {
      x86_64 = "1111111111111111111111111111111111111111111111111111111111111111"
    }
  }

  expect_failures = [var.sha256]
}

run "endpoint_must_be_https" {
  command = plan

  module {
    source = "./modules/sensor-ec2"
  }

  variables {
    endpoint = "http://sensor.example.com"
  }

  expect_failures = [var.endpoint]
}
