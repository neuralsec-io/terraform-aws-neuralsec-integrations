# Neuralsec sensor Terraform module for EC2: an SSM Command document that
# installs the sensor on the target instances, and the association that runs it
# on a schedule.
#
# The sensor authenticates with the instance role, so the instances need an
# instance profile carrying AmazonSSMManagedInstanceCore; the module stores no
# secret. The document is idempotent: the script skips the download when the
# installed binary already matches the pinned digest, and rewrites the unit on
# every run.

locals {
  # POSIX sh. `$${}` is not used: every shell variable is written as `$name` so
  # only `local.*` and `var.*` interpolations appear here.
  install_script = <<-EOT
    #!/bin/sh
    set -eu

    arch="$(uname -m)"
    case "$arch" in
      x86_64)
        expected_sha256="${lookup(var.sha256, "x86_64", "")}"
        ;;
      aarch64)
        expected_sha256="${lookup(var.sha256, "aarch64", "")}"
        ;;
      *)
        echo "unsupported architecture: $arch" >&2
        exit 1
        ;;
    esac

    binary=/usr/local/bin/neuralsec-sensor
    unit=/etc/systemd/system/neuralsec-sensor.service
    artifact_url="${var.artifact_base_url}/${var.sensor_version}/neuralsec-sensor-linux-$arch.tar.gz"

    # The digest pins the release archive; the archive digest of the installed
    # binary is recorded next to it, so a rerun skips the download.
    stamp=/usr/local/lib/neuralsec-sensor.sha256
    changed=0
    if [ -x "$binary" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$expected_sha256" ]; then
      echo "neuralsec-sensor already matches the pinned digest"
    else
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT

      if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp_dir/sensor.tar.gz" "$artifact_url"
      elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$tmp_dir/sensor.tar.gz" "$artifact_url"
      else
        echo "curl or wget is required to download the sensor" >&2
        exit 1
      fi

      actual_sha256="$(sha256sum "$tmp_dir/sensor.tar.gz" | awk '{print $1}')"
      if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "checksum mismatch for $artifact_url: expected $expected_sha256, got $actual_sha256" >&2
        exit 1
      fi

      tar -xzf "$tmp_dir/sensor.tar.gz" -C "$tmp_dir"
      install -m 0755 "$tmp_dir/neuralsec-sensor" "$binary"
      mkdir -p /usr/local/lib
      echo "$expected_sha256" > "$stamp"
      changed=1
    fi

    cat > "$unit.new" <<UNIT
    [Unit]
    Description=Neuralsec sensor
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    ExecStart=$binary
    Environment=RUNTIME_SENSOR_ENDPOINT=${var.endpoint}
    Environment=RUNTIME_SENSOR_PLATFORM=ec2
    AmbientCapabilities=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE
    CapabilityBoundingSet=CAP_BPF CAP_PERFMON CAP_SYS_RESOURCE
    NoNewPrivileges=yes
    ProtectSystem=strict
    ProtectHome=yes
    PrivateTmp=yes
    ReadOnlyPaths=-/sys/kernel/btf -/sys/fs/cgroup -/sys/kernel/tracing -/sys/kernel/debug
    MemoryMax=128M
    CPUQuota=20%
    Nice=10
    IOSchedulingClass=idle
    Restart=on-failure
    RestartSec=10
    StandardOutput=null

    [Install]
    WantedBy=multi-user.target
    UNIT

    if ! cmp -s "$unit.new" "$unit"; then
      mv "$unit.new" "$unit"
      changed=1
    else
      rm -f "$unit.new"
    fi

    systemctl daemon-reload
    systemctl enable neuralsec-sensor.service
    # A new binary or unit only takes effect on restart.
    if [ "$changed" = 1 ]; then
      systemctl restart neuralsec-sensor.service
    else
      systemctl start neuralsec-sensor.service
    fi
  EOT

  uninstall_script = <<-EOT
    #!/bin/sh
    set -eu

    systemctl disable --now neuralsec-sensor.service 2>/dev/null || true
    rm -f /etc/systemd/system/neuralsec-sensor.service
    rm -f /usr/local/bin/neuralsec-sensor /usr/local/lib/neuralsec-sensor.sha256
    systemctl daemon-reload
  EOT

  script = var.uninstall ? local.uninstall_script : local.install_script
}

resource "aws_ssm_document" "sensor" {
  name            = var.name_prefix
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = var.uninstall ? "Remove the Neuralsec sensor from an EC2 instance" : "Install the Neuralsec sensor on an EC2 instance"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = var.uninstall ? "uninstall" : "install"
        inputs = {
          runCommand = [local.script]
        }
      },
    ]
  })
}

resource "aws_ssm_association" "sensor" {
  name                = aws_ssm_document.sensor.name
  schedule_expression = var.schedule
  compliance_severity = "MEDIUM"

  dynamic "targets" {
    for_each = var.targets
    content {
      key    = targets.value.key
      values = targets.value.values
    }
  }
}
