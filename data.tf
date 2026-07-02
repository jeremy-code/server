data "oci_identity_availability_domains" "main" {
  compartment_id = oci_identity_compartment.main.id
}

data "oci_identity_availability_domain" "main" {
  compartment_id = oci_identity_compartment.main.id
  id             = (data.oci_identity_availability_domains.main.availability_domains[0]).id
}

data "oci_secrets_secretbundle" "database_passwords" {
  for_each = toset(local.database_usernames)

  secret_id = oci_vault_secret.database_passwords[each.key].id
}

data "oci_secrets_secretbundle" "cloudflare_tunnel_secret" {
  secret_id = oci_vault_secret.cloudflare_tunnel_secret.id
}

data "oci_secrets_secretbundle" "auth_client_secrets" {
  for_each = toset(local.auth_clients)

  secret_id = oci_vault_secret.auth_client_secrets[each.key].id
}

data "oci_secrets_secretbundle" "authelia_oidc_signing_key" {
  secret_id = oci_vault_secret.authelia_oidc_signing_key.id
}

data "oci_secrets_secretbundle" "authelia" {
  for_each = toset(local.authelia_secrets)

  secret_id = oci_vault_secret.authelia[each.key].id
}

data "oci_core_images" "main" {
  compartment_id = oci_identity_compartment.main.id
  # https://docs.oracle.com/en-us/iaas/images/ubuntu-2404/index.htm
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
}

data "oci_core_image" "main" {
  image_id = (data.oci_core_images.main.images[0]).id
}

data "oci_objectstorage_namespace" "main" {
  compartment_id = oci_identity_compartment.main.id
}

data "oci_email_dkim" "main" {
  dkim_id = oci_email_email_domain.main.active_dkim_id
}

data "oci_core_volume_backup_policies" "oracle_defined" {
  # https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/schedulingvolumebackups.htm
  filter {
    name   = "display_name"
    values = ["bronze", "silver", "gold"]
  }
}
