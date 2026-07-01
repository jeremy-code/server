variable "region" {
  type        = string
  description = "The region in which the resources will be deployed"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "The region must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "tenancy_ocid" {
  type        = string
  description = "The OCID of the tenancy"

  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "The OCID must be a tenancy OCID"
  }
}

variable "user_ocid" {
  type        = string
  description = "The OCID of the user"

  validation {
    condition     = startswith(var.user_ocid, "ocid1.user.")
    error_message = "The OCID must be a user OCID"
  }
}

/**
 * The following permissions are needed:
 * Account
 *   - Cloudflare Tunnel (Edit)
 * Zone
 *   - DNS (Edit)
 */
variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token"

  validation {
    condition     = startswith(var.cloudflare_api_token, "cfut_")
    error_message = "The Cloudflare API token must be valid"
  }
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID"
}

variable "server_domain" {
  type        = string
  description = "The domain name for the server"
}

variable "user_config" {
  type = object({
    email_address = string
    password      = string
  })
  description = "The configuration for the user"

  # Regex based on HTML standard used to validate `<input type=email>` by browsers
  # https://html.spec.whatwg.org/multipage/input.html#email-state-(type=email)
  validation {
    condition = can(
      regex(
        "^[\\w.!#$%&'*+\\/=?^`{|}~-]+@[[:alnum:]](?:[a-zA-Z0-9-]{0,61}[[:alnum:]])?(?:\\.[[:alnum:]](?:[a-zA-Z0-9-]{0,61}[[:alnum:]])?)*$",
        var.user_config.email_address
      )
    )
    error_message = "The email address must be valid"
  }
}

variable "rclone_config" {
  type = object({
    username = string
    password = string
  })
  description = "The Rclone user credentials for authenticating to the WebDAV server"
}

variable "fah_config" {
  type = object({
    token   = string
    passkey = string
    team    = number
    user    = string
  })
  description = "The configuration for the Folding@home client"

  validation {
    condition = can(
      regex("[[:xdigit:]]{32}", var.fah_config.passkey)
    ) && var.fah_config.team >= 0 && var.fah_config.team <= (pow(2, 31) - 1)
    error_message = "The passkey must be a 32-character hexadecimal string. The team number must be between 0 and 2^31 - 1 (2,147,483,647)"
  }
}
