resource "oci_identity_compartment" "main" {
  compartment_id = var.tenancy_ocid
  description    = "Compartment for home server."
  name           = "server-compartment"
}

data "oci_identity_availability_domains" "main" {
  compartment_id = oci_identity_compartment.main.id
}

data "oci_identity_availability_domain" "main" {
  compartment_id = oci_identity_compartment.main.id
  id             = (data.oci_identity_availability_domains.main.availability_domains[0]).id
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
  cidr_blocks    = ["192.168.0.0/16"] # RFC 1918
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
  display_name   = "Main Comppute Instance Security List"
  vcn_id         = oci_core_vcn.main.id

  ingress_security_rules {
    description = "Allow SSH traffic from RRWE"
    # RRWE, Charter Communications Inc (AS20001)
    # https://whois.arin.net/rest/net/NET-23-240-0-0-1
    source      = "23.240.0.0/14"
    source_type = "CIDR_BLOCK"
    protocol    = 6 # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    description = "Allow SSH traffic from RR_WEST-2BLK"
    # RR_WEST-2BLK, Charter Communications Inc (AS20001)
    # https://whois.arin.net/rest/net/NET-66-74-0-0-1
    source      = "66.74.0.0/15"
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
  cidr_block          = local.instance_subnet_cidr_blocks[0]
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
  cidr_block          = local.database_subnet_cidr_blocks[0]
  compartment_id      = oci_identity_compartment.main.id
  display_name        = "Main MySQL Database System Subnet"
  dns_label           = "database"
  security_list_ids   = [oci_core_security_list.database.id]
  vcn_id              = oci_core_vcn.main.id
}

locals {
  enabled_plugin_names = [
    "Vulnerability Scanning",
    "Management Agent",
    "Cloud Guard Workload Protection",
    "Block Volume Management",
    "Bastion"
  ]
  disabled_plugin_names = [
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

resource "oci_mysql_mysql_db_system" "main" {
  admin_username      = "admin"
  admin_password      = var.mysql_admin_password
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
  }
}

data "oci_objectstorage_namespace" "main" {
  compartment_id = oci_identity_compartment.main.id
}

resource "oci_objectstorage_bucket" "main" {
  access_type    = "NoPublicAccess"
  compartment_id = oci_identity_compartment.main.id
  name           = "main-bucket"
  namespace      = data.oci_objectstorage_namespace.main.namespace
  storage_tier   = "Standard"
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
    user_data = base64encode(
      format(
        "%s\n%s",
        file("${path.module}/cloud-init.yml"),
        yamlencode(
          {
            write_files = [
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
                path    = "/home/ubuntu/htpasswd",
                content = "${var.rclone_config.username}:${bcrypt(var.rclone_config.password)}"
              },
              {
                path = "/home/ubuntu/cloudflared-credentials-file.json",
                content = jsonencode({
                  AccountTag   = var.cloudflared_config.account_tag,
                  TunnelID     = var.cloudflared_config.tunnel_id,
                  TunnelSecret = var.cloudflared_config.tunnel_secret
                })
              },

              {
                path = "/home/ubuntu/docker-compose.yml",
                content = templatefile("${path.module}/docker-compose.yml.tftpl", {
                  server_domain = var.server_domain
                  my_sql_config = {
                    admin_username = oci_mysql_mysql_db_system.main.admin_username
                    admin_password = urlencode(oci_mysql_mysql_db_system.main.admin_password)
                    host           = oci_mysql_mysql_db_system.main.ip_address
                    port           = oci_mysql_mysql_db_system.main.port
                  }
                  oos_config = {
                    bucket_name         = oci_objectstorage_bucket.main.name
                    region              = var.region
                    namespace           = data.oci_objectstorage_namespace.main.namespace
                    compartment_id      = oci_identity_compartment.main.id
                    bucket_storage_tier = oci_objectstorage_bucket.main.storage_tier
                  }
                  cloudflared_tunnel_id = var.cloudflared_config.tunnel_id,
                  fah_config            = var.fah_config
                })
              }
            ]
          }
        )
    ))
  }
  shape = data.oci_core_images.main.shape
  shape_config {
    baseline_ocpu_utilization = "BASELINE_1_1"
    memory_in_gbs             = 24
    ocpus                     = 4
  }
  source_details {
    boot_volume_size_in_gbs         = 50
    boot_volume_vpus_per_gb         = 10
    source_type                     = "image"
    source_id                       = data.oci_core_image.main.id
    is_preserve_boot_volume_enabled = true
  }

  lifecycle {
    # Due to bcrypt, which uses a random salt, the base64-encoded value will change every time
    ignore_changes = [metadata]
  }
}

resource "oci_identity_dynamic_group" "instance" {
  compartment_id = var.tenancy_ocid
  description    = "Dynamic group for the main instance."
  matching_rule  = "instance.id = '${oci_core_instance.main.id}'"
  name           = "main-instance-dynamic-group"
}

resource "oci_identity_policy" "instance-policy" {
  compartment_id = oci_identity_compartment.main.id
  description    = "Allow storage bucket read/write access to the main instance."
  name           = "main-instance-policy"
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
