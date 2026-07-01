resource "oci_core_vcn" "main" {
  cidr_blocks    = ["192.168.0.0/16"] # RFC 1918 (https://datatracker.ietf.org/doc/html/rfc1918#section-3)
  compartment_id = oci_identity_compartment.main.id
  display_name   = "Main Virtual Cloud Network (VCN)"
  dns_label      = "internal"
  is_ipv6enabled = false
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

  ingress_security_rules {
    description = "Allow WireGuard traffic"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = 17 # UDP
    udp_options {
      min = 51820
      max = 51820
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

locals {
  instance_subnet_cidr_blocks = [for cidr_block in oci_core_vcn.main.cidr_blocks : cidrsubnet(cidr_block, 8, 20)]
  database_subnet_cidr_blocks = [for cidr_block in oci_core_vcn.main.cidr_blocks : cidrsubnet(cidr_block, 8, 21)]
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
