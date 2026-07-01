terraform {
  required_version = "~> 1.15"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.19"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
