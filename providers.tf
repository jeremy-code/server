provider "oci" {
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid
  region              = var.region
  auth                = "SecurityToken"
  config_file_profile = "DEFAULT"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
