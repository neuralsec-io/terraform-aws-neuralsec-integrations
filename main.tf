# Registry root module.
#
# The components are submodules under `modules/`, consumed as
# `neuralsec-io/neuralsec-integrations/aws//modules/<name>`. This root holds no
# resources: it keeps the repository discoverable in the Terraform Registry and
# gives `terraform init` and `terraform test` a working directory for the tests
# under `tests/`.
