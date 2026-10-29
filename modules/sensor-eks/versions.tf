terraform {
  required_version = ">= 1.4.0"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # 2.17 is the last 2.x release; the one resource and the attributes below
      # are identical in 2.x and 3.x, so one constraint covers both.
      version = ">= 2.17.0, < 4.0"
    }
  }
}
