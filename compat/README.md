# Minimum-version check

`scripts/check-min-versions.sh` runs this root at the oldest Terraform, OpenTofu
and AWS provider versions the modules support. `sensor-lambda` needs Terraform
1.6 and AWS provider 5.0, so it has its own root in `sensor-lambda/`, checked at
its own floor. `sensor-eks` needs the Helm provider 2.17 or newer, so it has its
own root in `sensor-eks/`, checked at the 2.17 floor and against the 3.x line.
