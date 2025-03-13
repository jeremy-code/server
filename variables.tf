variable "region" {
  type        = string
  description = "The region in which the resources will be deployed"
}

variable "tenancy_ocid" {
  type        = string
  description = "The OCID of the tenancy"
}

variable "user_ocid" {
  type        = string
  description = "The OCID of the user"
}

variable "mysql_admin_password" {
  type        = string
  description = "The password for the MySQL database"
}

variable "cloudflared_account_tag" {
  type        = string
  description = "Account tag for Cloudflare"
}

variable "cloudflared_tunnel_id" {
  type        = string
  description = "The ID of the Cloudflare Tunnel"
}

variable "cloudflared_tunnel_secret" {
  type        = string
  description = "The secret for the Cloudflare Tunnel"
}


variable "fah_token" {
  type        = string
  description = "The token for the Folding@home client"
}

variable "fah_passkey" {
  type        = string
  description = "The passkey for the Folding@home client"
}

variable "fah_team" {
  type        = number
  description = "The team number for the Folding@home client"
}

variable "fah_user" {
  type        = string
  description = "The username for the Folding@home client"
}
