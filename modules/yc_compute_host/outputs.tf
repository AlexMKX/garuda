output "instance_id" {
  description = "YC compute instance id."
  value       = yandex_compute_instance.this.id
}

output "public_ipv4" {
  description = "One-to-one NAT public IPv4 on the primary NIC; null when nat=false."
  value       = var.nat ? yandex_compute_instance.this.network_interface[0].nat_ip_address : null
}

output "private_ipv4" {
  description = "Private IPv4 on the primary NIC."
  value       = yandex_compute_instance.this.network_interface[0].ip_address
}

output "fqdn" {
  description = "FQDN assigned by YC."
  value       = yandex_compute_instance.this.fqdn
}

output "hostname" {
  description = "Linux hostname configured on the instance."
  value       = yandex_compute_instance.this.hostname
}

output "zone" {
  description = "Zone where the instance lives."
  value       = yandex_compute_instance.this.zone
}

output "folder_id" {
  description = "Folder id where the instance lives."
  value       = yandex_compute_instance.this.folder_id
}

output "subnet_id" {
  description = "Subnet id of the primary NIC."
  value       = yandex_compute_instance.this.network_interface[0].subnet_id
}

output "network_id" {
  description = "Network id of the primary subnet (from var.network_id if provided, otherwise from subnet data source)."
  value       = var.network_id != null ? var.network_id : data.yandex_vpc_subnet.primary.network_id
}

output "security_group_ids" {
  description = "Effective SGs attached to the primary NIC."
  value       = yandex_compute_instance.this.network_interface[0].security_group_ids
}

output "platform_id" {
  description = "YC compute platform id."
  value       = yandex_compute_instance.this.platform_id
}

output "boot_disk_id" {
  description = "Id of the boot disk."
  value       = yandex_compute_instance.this.boot_disk[0].disk_id
}

output "ssh_user" {
  description = "Linux user created by cloud-init."
  value       = var.ssh_user
}

output "ssh_private_key_openssh" {
  description = "OpenSSH-formatted private key for the module-managed user (always generated)."
  value       = tls_private_key.admin.private_key_openssh
  sensitive   = true
}

output "connection_data" {
  description = "Ansible/Terraform-friendly connection bundle for this host. Matches the connection_data variable type used by Linux workload modules. instance_token = yandex_compute_instance.id, used downstream as an opaque substrate-generation discriminator that forces ansible re-apply on VM recreate."
  sensitive   = true
  value = {
    host                 = var.nat ? yandex_compute_instance.this.network_interface[0].nat_ip_address : yandex_compute_instance.this.network_interface[0].ip_address
    user                 = var.ssh_user
    connection           = "ssh"
    network_os           = "linux"
    password             = null
    ssh_private_key_file = null
    ssh_private_key      = tls_private_key.admin.private_key_openssh
    instance_token       = yandex_compute_instance.this.id
  }
}

# --- Testing-only outputs ------------------------------------------------
# Expose the rendered ssh-keys metadata string and cloud-init user-data so
# terraform tests can assert on the exact values fed into the instance,
# unaffected by lifecycle.ignore_changes on the instance resource.
output "test_ssh_keys_metadata" {
  description = "Internal: rendered YC ssh-keys metadata string. Testing use only."
  sensitive   = true
  value       = local.ssh_keys_metadata
}

output "test_cloud_init_user_data" {
  description = <<-EOT
    Internal: rendered cloud-init user-data MIME bundle. Testing use only.
    Returns null when no cloud-init payload is needed (no data disk and
    user_data_parts is empty). Otherwise: plaintext multipart MIME
    (gzip=false, base64_encode=false in the cloudinit_config data source)
    matching what the VM receives via metadata['user-data'].
  EOT
  sensitive   = true
  value       = local.needs_cloud_init ? data.cloudinit_config.this[0].rendered : null
}
