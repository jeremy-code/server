output "compartment" {
  value = {
    id   = oci_identity_compartment.main.id
    name = oci_identity_compartment.main.name
  }
}

output "avaliability_domain" {
  value = {
    id        = data.oci_identity_availability_domain.main.id
    ad_number = data.oci_identity_availability_domain.main.ad_number
    name      = data.oci_identity_availability_domain.main.name
  }
}

output "image" {
  value = {
    display_name         = data.oci_core_image.main.display_name
    id                   = data.oci_core_image.main.id
    operating_system     = "${data.oci_core_image.main.operating_system} ${data.oci_core_image.main.operating_system_version}"
    billable_size_in_gbs = data.oci_core_image.main.billable_size_in_gbs
    size_in_mbs          = data.oci_core_image.main.size_in_mbs
  }
}

output "instance_subnet" {
  value = {
    id         = oci_core_subnet.instance.id
    cidr_block = oci_core_subnet.instance.cidr_block
    dns_label  = oci_core_subnet.instance.dns_label
  }
}

output "database_subnet" {
  value = {
    id         = oci_core_subnet.database.id
    cidr_block = oci_core_subnet.database.cidr_block
    dns_label  = oci_core_subnet.database.dns_label
  }
}

output "volumes" {
  value = [oci_core_instance.main.boot_volume_id, oci_core_volume.block.id]
}

output "instance" {
  value = {
    private_ip = oci_core_instance.main.private_ip
    public_ip  = oci_core_instance.main.public_ip
    shape = {
      shape                        = oci_core_instance.main.shape
      baseline_ocpu_utilization    = oci_core_instance.main.shape_config[0].baseline_ocpu_utilization
      gpus                         = oci_core_instance.main.shape_config[0].gpus
      memory_in_gbs                = oci_core_instance.main.shape_config[0].memory_in_gbs
      networking_bandwidth_in_gbps = oci_core_instance.main.shape_config[0].networking_bandwidth_in_gbps
      cpus                         = format("%s OCPUs, %s VCPUs", oci_core_instance.main.shape_config[0].ocpus, oci_core_instance.main.shape_config[0].vcpus)
      processor_description        = oci_core_instance.main.shape_config[0].processor_description
    }
    source_details = {
      boot_volume_size_in_gbs = oci_core_instance.main.source_details[0].boot_volume_size_in_gbs
      boot_volume_vpus_per_gb = oci_core_instance.main.source_details[0].boot_volume_vpus_per_gb
      source_type             = oci_core_instance.main.source_details[0].source_type
    }
  }
}
