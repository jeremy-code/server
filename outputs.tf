
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
    id           = oci_core_instance.main.id
    display_name = oci_core_instance.main.display_name
    private_ip   = oci_core_instance.main.private_ip
    public_ip    = oci_core_instance.main.public_ip
  }
}
