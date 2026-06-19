terraform {
  required_version = "~> 1.15"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.19"
    }
  }
}
