resource "oci_identity_compartment" "main" {
  compartment_id = var.tenancy_ocid
  description    = "Compartment for home server."
  name           = "server_compartment"
}

data "oci_identity_availability_domains" "main" {
  compartment_id = oci_identity_compartment.main.id
}

data "oci_identity_availability_domain" "main" {
  compartment_id = oci_identity_compartment.main.id
  id             = (data.oci_identity_availability_domains.main.availability_domains[0]).id
}

resource "oci_kms_vault" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main vault"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "main" {
  compartment_id      = oci_identity_compartment.main.id
  display_name        = "Main key"
  management_endpoint = oci_kms_vault.main.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

resource "oci_vault_secret" "mysql_db_password" {
  compartment_id         = oci_identity_compartment.main.id
  key_id                 = oci_kms_key.main.id
  secret_name            = "mysql_db_password"
  vault_id               = oci_kms_vault.main.id
  description            = "MySQL database password"
  enable_auto_generation = true

  secret_generation_context {
    generation_template = "DBAAS_DEFAULT_PASSWORD"
    generation_type     = "PASSPHRASE"
    passphrase_length   = 16
  }
}

data "oci_secrets_secretbundle" "mysql_db_password" {
  secret_id = oci_vault_secret.mysql_db_password.id
}

resource "oci_vault_secret" "cloudflare_tunnel_secret" {
  compartment_id = oci_identity_compartment.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = "cloudflare_tunnel_secret"
  vault_id       = oci_kms_vault.main.id
  description    = "Cloudflare tunnel secret"
}

data "oci_secrets_secretbundle" "cloudflare_tunnel_secret" {
  secret_id = oci_vault_secret.cloudflare_tunnel_secret.id
}

locals {
  mysql_db_password        = one(data.oci_secrets_secretbundle.mysql_db_password.secret_bundle_content[*].content)
  cloudflare_tunnel_secret = one(data.oci_secrets_secretbundle.cloudflare_tunnel_secret.secret_bundle_content[*].content)
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id    = var.cloudflare_account_id
  name          = "*.${var.server_domain}"
  config_src    = "cloudflare"
  tunnel_secret = local.cloudflare_tunnel_secret
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

resource "oci_core_vcn" "main" {
  cidr_blocks    = ["192.168.0.0/16"] # RFC 1918 (https://datatracker.ietf.org/doc/html/rfc1918#section-3)
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Virtual Cloud Network (VCN)"
  dns_label      = "internal"
  is_ipv6enabled = false
}

locals {
  instance_subnet_cidr_blocks = [for cidr_block in oci_core_vcn.main.cidr_blocks : cidrsubnet(cidr_block, 8, 20)]
  database_subnet_cidr_blocks = [for cidr_block in oci_core_vcn.main.cidr_blocks : cidrsubnet(cidr_block, 8, 21)]
}

resource "oci_core_security_list" "instance" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Compute Instance Security List"
  vcn_id         = oci_core_vcn.main.id

  ingress_security_rules {
    description = "Allow SSH traffic from RRWE"
    # RRWE, Charter Communications Inc (AS20001)
    # https://whois.arin.net/rest/net/NET-172-88-0-0-1
    source      = "172.88.0.0/14"
    source_type = "CIDR_BLOCK"
    protocol    = 6 # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }

  # TODO: Limit egress traffic to only necessary destinations (e.g. Cloudflare,
  # Ubuntu, Docker, Oracle, etc.)
  egress_security_rules {
    description      = "Allow all other egress traffic"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Internet Gateway"
  vcn_id         = oci_core_vcn.main.id
}

resource "oci_core_route_table" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Route Table with Internet Gateway"
  route_rules {
    description       = "Default route for internet gateway"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
  vcn_id = oci_core_vcn.main.id
}

resource "oci_core_subnet" "instance" {
  availability_domain = data.oci_identity_availability_domain.main.name
  cidr_block          = one(local.instance_subnet_cidr_blocks)
  compartment_id      = oci_identity_compartment.main.id
  display_name        = "Main Compute Instance Subnet"
  dns_label           = "instance"
  route_table_id      = oci_core_route_table.main.id
  security_list_ids   = [oci_core_security_list.instance.id]
  vcn_id              = oci_core_vcn.main.id
}

resource "oci_core_security_list" "database" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Database Security List"
  vcn_id         = oci_core_vcn.main.id

  ingress_security_rules {
    description = "Allow MySQL traffic from the main instance subnet (3306)"
    source      = oci_core_subnet.instance.cidr_block
    source_type = "CIDR_BLOCK"
    protocol    = 6 # TCP
    tcp_options {
      min = 3306
      max = 3306
    }
  }

  ingress_security_rules {
    description = "Allow MySQL traffic from the main instance subnet (33060)"
    source      = oci_core_subnet.instance.cidr_block
    source_type = "CIDR_BLOCK"
    protocol    = 6 # TCP
    tcp_options {
      min = 33060
      max = 33060
    }
  }
}

resource "oci_core_subnet" "database" {
  availability_domain = data.oci_identity_availability_domain.main.name
  cidr_block          = one(local.database_subnet_cidr_blocks)
  compartment_id      = oci_identity_compartment.main.id
  display_name        = "Main MySQL Database System Subnet"
  dns_label           = "database"
  security_list_ids   = [oci_core_security_list.database.id]
  vcn_id              = oci_core_vcn.main.id
}

resource "oci_mysql_mysql_db_system" "main" {
  admin_username      = "admin"
  admin_password      = base64decode(local.mysql_db_password)
  availability_domain = data.oci_identity_availability_domain.main.name
  compartment_id      = oci_identity_compartment.main.id
  crash_recovery      = "ENABLED"
  data_storage {
    is_auto_expand_storage_enabled = false
  }
  customer_contacts {
    email = var.email_address
  }
  data_storage_size_in_gb = 50
  database_management     = "DISABLED"
  database_mode           = "READ_WRITE"
  deletion_policy {
    automatic_backup_retention = "RETAIN"
    final_backup               = "REQUIRE_FINAL_BACKUP"
    is_delete_protected        = true
  }
  description         = "MySQL database system for use with Vaultwarden."
  display_name        = "Main MySQL DB System"
  hostname_label      = "mysql"
  is_highly_available = false
  port                = 3306
  port_x              = 33060
  read_endpoint {
    is_enabled = false
  }
  shape_name = "MySQL.Free"
  subnet_id  = oci_core_subnet.database.id

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      # Per manually updating password in console instead of destroying it
      admin_password,
    ]
  }
}

data "oci_objectstorage_namespace" "main" {
  compartment_id = oci_identity_compartment.main.id
}

resource "oci_objectstorage_bucket" "main" {
  access_type    = "NoPublicAccess"
  auto_tiering   = "InfrequentAccess"
  compartment_id = oci_identity_compartment.main.id
  name           = "main-bucket"
  namespace      = data.oci_objectstorage_namespace.main.namespace
  storage_tier   = "Standard"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_email_email_domain" "main" {
  name           = var.server_domain
  compartment_id = oci_identity_compartment.main.id
  description    = "Email domain for home server."
}

data "oci_email_dkim" "main" {
  dkim_id = oci_email_email_domain.main.active_dkim_id
}

resource "oci_email_email_return_path" "main" {
  name               = "mail.${var.server_domain}"
  description        = "Custom return path (bounce address) for domain mail.${var.server_domain}"
  parent_resource_id = oci_email_email_domain.main.id
}

resource "oci_identity_smtp_credential" "main" {
  user_id     = var.user_ocid
  description = "Main SMTP credentials"
}

resource "oci_email_sender" "senders" {
  for_each = toset(["vault", "status"])

  compartment_id = oci_identity_compartment.main.id
  email_address  = "${each.value}@${var.server_domain}"
}

locals {
  enabled_plugin_names = [
    "Vulnerability Scanning",
    "Cloud Guard Workload Protection",
    "Block Volume Management",
  ]
  disabled_plugin_names = [
    "Bastion",
    "Management Agent",
    "Oracle Autonomous Linux",
    "OS Management Service Agent",
    "Custom Logs Monitoring",
    "Compute Instance Run Command",
  ]

  plugins_config = concat(
    [for plugin_name in local.enabled_plugin_names : {
      desired_state = "ENABLED"
      name          = plugin_name
    }],
    [for plugin_name in local.disabled_plugin_names : {
      desired_state = "DISABLED"
      name          = plugin_name
  }])
}

locals {
  cloud_init_write_files = [
    {
      path        = "/etc/ssh/sshd_config.d/99-google-authenticator.conf",
      content     = file("${path.module}/files/99-google-authenticator.conf"),
      owner       = "root:root",
      permissions = "0644",
    },
    {
      path        = "/etc/pam.d/sshd",
      content     = file("${path.module}/files/sshd"),
      owner       = "root:root",
      permissions = "0644",
    },
    {
      path    = "/etc/sysctl.d/local.conf",
      content = <<-EOF
                # See https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
                # Defaults to 212,992 bytes = 208 KiB. Update to 7,864,000 bytes = 7.5 MiB
                net.core.rmem_max = 7864000
                net.core.wmem_max = 7864000
                EOF
    },
    {
      path        = "/etc/environment",
      owner       = "root:root",
      permissions = "0644",
      append      = true,
      content     = <<-EOF
                # https://manpages.ubuntu.com/manpages/noble/man8/pam_env.8.html

                # Docker CLI
                # https://docs.docker.com/reference/cli/docker/#environment-variables

                # Enable Docker Content Trust, which must be set with an
                # environment variable for `docker compose up`
                DOCKER_CONTENT_TRUST=1

                # Docker Compose
                # https://docs.docker.com/compose/how-tos/environment-variables/envvars/

                COMPOSE_FILE=/home/jeremy/docker-compose.yml
                COMPOSE_REMOVE_ORPHANS=1
                EOF
    },
    {
      path        = "/etc/logrotate.conf",
      owner       = "root:root",
      permissions = "0644",
      append      = true,
      content     = file("${path.module}/files/logrotate.conf")
    },
    {
      path    = "/home/jeremy/.env",
      content = <<-EOF
                FRESHRSS_EMAIL=${var.freshrss_config.email}
                FRESHRSS_PASSWORD=${var.freshrss_config.password}
                EOF
    },
    {
      path    = "/home/jeremy/opml.xml",
      content = file("${path.module}/files/opml.xml"),
    },
    {
      path    = "/home/jeremy/htpasswd",
      content = "${var.rclone_config.username}:${bcrypt(var.rclone_config.password)}",
      # https://github.com/rclone/rclone/blob/master/Dockerfile#L48
      permissions = "0440",
      owner       = "jeremy:jeremy",
      # Wait until user is created
      defer = true,
    },
    {
      path = "/home/jeremy/vaultwarden-database-url",
      content = join("", [
        "mysql://",
        oci_mysql_mysql_db_system.main.admin_username,
        ":",
        urlencode(base64decode(local.mysql_db_password)),
        "@",
        oci_mysql_mysql_db_system.main.ip_address,
        ":",
        oci_mysql_mysql_db_system.main.port,
        "/vaultwarden"
      ]),
    },
    {
      path    = "/home/jeremy/gatus-config.yaml",
      content = file("${path.module}/files/gatus-config.yaml"),
    },
    {
      path = "/home/jeremy/cloudflared-credentials-file.json",
      content = jsonencode({
        AccountTag   = cloudflare_zero_trust_tunnel_cloudflared.main.account_tag
        TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.main.id
        TunnelSecret = local.cloudflare_tunnel_secret
      }),
    },
    {
      path = "/home/jeremy/rclone.conf",
      content = templatefile("${path.module}/templates/rclone.conf.tftpl", {
        oos_config = {
          bucket_name         = oci_objectstorage_bucket.main.name
          region              = var.region
          namespace           = data.oci_objectstorage_namespace.main.namespace
          compartment_id      = oci_identity_compartment.main.id
          bucket_storage_tier = oci_objectstorage_bucket.main.storage_tier
        }
      })
    },
    {
      path = "/home/jeremy/fah.config.xml",
      content = templatefile("${path.module}/templates/fah.config.xml.tftpl", {
        fah_config = var.fah_config
      })
    },
    {
      path = "/home/jeremy/cloudflare.config.yml",
      content = templatefile("${path.module}/templates/cloudflare.config.yml.tftpl", {
        server_domain         = var.server_domain
        cloudflared_tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.main.id
      })
    },
    {
      path = "/home/jeremy/docker-compose.yml",
      content = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
        server_domain = var.server_domain
        bucket_name   = oci_objectstorage_bucket.main.name
        gatus_config = {
          username                = var.gatus_config.username
          encoded_hashed_password = base64encode(bcrypt(var.gatus_config.password, 9))
        }
        cloudflared_tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.main.id
        smtp_config = {
          username = oci_identity_smtp_credential.main.username
          password = oci_identity_smtp_credential.main.password
          host     = "smtp.email.${var.region}.oci.oraclecloud.com"
        }
        email = {
          vaultwarden = oci_email_sender.senders["vault"].email_address
          gatus       = oci_email_sender.senders["status"].email_address
          owner       = var.email_address
        }
      })
    }
  ]
  cloud_init = base64encode(
    # Append write_files manually
    format(
      "%s\n%s",
      file("${path.module}/files/cloud-init.yml"),
      yamlencode({
        write_files = local.cloud_init_write_files
      })
    )
  )
}

resource "oci_core_instance" "main" {
  agent_config {
    dynamic "plugins_config" {
      for_each = local.plugins_config
      content {
        desired_state = plugins_config.value.desired_state
        name          = plugins_config.value.name
      }
    }
  }
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
  availability_domain = data.oci_identity_availability_domain.main.name
  compartment_id      = oci_identity_compartment.main.id
  create_vnic_details {
    assign_ipv6ip    = false
    assign_public_ip = true
    display_name     = "Main Compute Instance VNIC"
    hostname_label   = "instance"
    subnet_id        = oci_core_subnet.instance.id
  }
  display_name                        = "Main Compute Instance"
  is_pv_encryption_in_transit_enabled = true
  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = true
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }
  metadata = {
    user_data = local.cloud_init
  }
  shape = data.oci_core_images.main.shape
  shape_config {
    baseline_ocpu_utilization = "BASELINE_1_1"
    memory_in_gbs             = 12
    ocpus                     = 2
  }
  source_details {
    boot_volume_size_in_gbs         = 50
    boot_volume_vpus_per_gb         = 10
    source_type                     = "image"
    source_id                       = data.oci_core_image.main.id
    is_preserve_boot_volume_enabled = true
  }

  lifecycle {
    ignore_changes = [
      # Since the `bcrypt` function always uses a random salt, the Base64-encoded
      # value will change on each run even when the value is the same. Hence, to
      # prevent unnecessary destructions, changes to the `metadata` attribute are
      # ignored. When the metadata actually changes, run `terraform plan` or
      # `terraform apply` with `-replace="oci_core_instance.main"` to force
      # replacement (or comment out this line).
      # metadata
    ]
  }
}

resource "oci_identity_dynamic_group" "instance" {
  compartment_id = var.tenancy_ocid
  description    = "Dynamic group for the main instance."
  matching_rule  = "instance.id = '${oci_core_instance.main.id}'"
  name           = "main_instance_dynamic_group"
}

resource "oci_identity_policy" "instance" {
  compartment_id = oci_identity_compartment.main.id
  description    = "Allow storage bucket read/write access to the main instance."
  name           = "main_instance_policy"
  # https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm
  statements = [
    "Allow dynamic-group '${oci_identity_dynamic_group.instance.name}' to manage objectstorage-namespaces in compartment ${oci_identity_compartment.main.name}",
    "Allow dynamic-group '${oci_identity_dynamic_group.instance.name}' to use buckets in compartment ${oci_identity_compartment.main.name} where target.bucket.name = '${oci_objectstorage_bucket.main.name}'",
    "Allow dynamic-group '${oci_identity_dynamic_group.instance.name}' to manage objects in compartment ${oci_identity_compartment.main.name} where target.bucket.name = '${oci_objectstorage_bucket.main.name}'"
  ]
}

resource "oci_core_volume" "block" {
  availability_domain = data.oci_identity_availability_domain.main.name
  compartment_id      = oci_identity_compartment.main.id
  display_name        = "Main Instance Block Volume"
  size_in_gbs         = 50
  vpus_per_gb         = 0

  autotune_policies {
    autotune_type = "DETACHED_VOLUME"
  }
}

data "oci_core_volume_backup_policies" "oracle_defined" {
  # https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/schedulingvolumebackups.htm
  filter {
    name   = "display_name"
    values = ["bronze", "silver", "gold"]
  }
}

locals {
  # Weekly incremental backups: At midnight Sunday. Retain 4 weeks.
  # Monthly incremental backups: At midnight on the 1st of the month. Retain 12
  #                              months.
  # Yearly full backups: At midnight January 1. Retain 5 years.
  silver_volume_backup_policy = one(
    [
      for policy in data.oci_core_volume_backup_policies.oracle_defined.volume_backup_policies
      : policy
      if policy.display_name == "silver"
    ]
  )
}

resource "oci_core_volume_backup_policy_assignment" "main" {
  for_each = tomap({
    boot_volume_id  = oci_core_instance.main.boot_volume_id
    block_volume_id = oci_core_volume.block.id
  })

  asset_id  = each.value
  policy_id = local.silver_volume_backup_policy.id
}

resource "oci_core_volume_attachment" "block" {
  attachment_type                   = "iscsi"
  device                            = "/dev/oracleoci/oraclevdb"
  display_name                      = "Main Instance Block Volume Attachment"
  instance_id                       = oci_core_instance.main.id
  is_agent_auto_iscsi_login_enabled = true
  use_chap                          = false
  volume_id                         = oci_core_volume.block.id
}
