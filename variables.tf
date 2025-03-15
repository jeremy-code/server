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

variable "server_domain" {
  type        = string
  description = "The domain name for the server"
}

variable "mysql_admin_password" {
  type        = string
  description = "The password for the MySQL database"

  validation {
    # https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.52.1/oci_cli_docs/cmdref/mysql/db-system/create.html#cmdoption-admin-password
    condition = length(
      var.mysql_admin_password
      ) >= 8 && length(
      var.mysql_admin_password
      ) <= 32 && length(
      regexall("[[:digit:]]", var.mysql_admin_password)
      ) > 0 && length(
      regexall("[[:lower:]]", var.mysql_admin_password)
      ) > 0 && length(
      regexall("[[:upper:]]", var.mysql_admin_password)
      ) > 0 && length(
      regexall("[^0-9A-Za-z]", var.mysql_admin_password)
    ) > 0
    error_message = "The password must be between 8 and 32 characters long and contain at least 1 numeric, lowercase, uppercase, and special (non-alphanumeric) character"
  }
}

variable "email_address" {
  type        = string
  description = "The email address to contact for alerts"

  # Regex based on HTML standard used to validate `<input type=email>` by browsers
  # https://html.spec.whatwg.org/multipage/input.html#email-state-(type=email)
  validation {
    condition = can(
      regex(
        "^[\\w.!#$%&'*+\\/=?^`{|}~-]+@[[:alnum:]](?:[a-zA-Z0-9-]{0,61}[[:alnum:]])?(?:\\.[[:alnum:]](?:[a-zA-Z0-9-]{0,61}[[:alnum:]])?)*$",
        var.email_address
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

variable "gatus_config" {
  type = object({
    username = string
    password = string
  })
  description = "The credentials for Gatus basic authentication"
}

variable "cloudflared_config" {
  type = object({
    account_tag   = string
    tunnel_id     = string
    tunnel_secret = string
  })
  description = "The configuration for cloudflared"

  validation {
    condition     = can(base64decode(var.cloudflared_config.tunnel_secret)) && length(base64decode(var.cloudflared_config.tunnel_secret)) >= 32
    error_message = "The tunnel secret must be a Base64-encoded string of at least 32 bytes"
  }
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
