output "instance_id" {
  description = "GCE compute instance self_link (used as a stable resource identifier)."
  value       = google_compute_instance.this.self_link
}

output "public_ipv4" {
  description = "External IPv4 on the primary NIC (nat_ip)."
  value       = try(google_compute_instance.this.network_interface[0].access_config[0].nat_ip, null)
}

output "private_ipv4" {
  description = "Internal IPv4 on the primary NIC."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "hostname" {
  description = "Instance name (used as Linux hostname)."
  value       = google_compute_instance.this.name
}

output "project_id" {
  description = "Project id the instance lives in."
  value       = google_compute_instance.this.project
}

output "region" {
  description = "Region the instance lives in (from input; GCE instance carries only zone)."
  value       = var.region
}

output "zone" {
  description = "Zone the instance lives in."
  value       = google_compute_instance.this.zone
}

output "network" {
  description = "VPC network self_link."
  value       = google_compute_instance.this.network_interface[0].network
}

output "subnetwork" {
  description = "Subnetwork self_link (nullable)."
  value       = try(google_compute_instance.this.network_interface[0].subnetwork, null)
}

output "network_tags" {
  description = "Full set of network tags on the instance (includes module-managed firewall tag)."
  value       = google_compute_instance.this.tags
}

output "service_account_email" {
  description = "Service account email attached to the instance (nullable)."
  value       = try(google_compute_instance.this.service_account[0].email, null)
}

output "ssh_user" {
  description = "Linux user created by cloud-init."
  value       = var.ssh_user
}

output "boot_disk_source" {
  description = "Source self_link/image of the boot disk."
  value       = google_compute_instance.this.boot_disk[0].source
}

output "static_ip_address_id" {
  description = "Id of the module-managed google_compute_address; null when allocate_static_ip=false."
  value       = try(google_compute_address.this[0].id, null)
}

output "ssh_private_key_openssh" {
  description = "OpenSSH-formatted private key for the module-managed user (always generated)."
  value       = tls_private_key.admin.private_key_openssh
  sensitive   = true
}

output "connection_data" {
  description = "Ansible/Terraform-friendly connection bundle for this host. Matches the connection_data variable type used by Linux workload modules. instance_token = google_compute_instance.self_link, used downstream as an opaque substrate-generation discriminator that forces ansible re-apply on VM recreate."
  sensitive   = true
  value = {
    host                 = try(google_compute_instance.this.network_interface[0].access_config[0].nat_ip, google_compute_instance.this.network_interface[0].network_ip)
    user                 = var.ssh_user
    connection           = "ssh"
    network_os           = "linux"
    password             = null
    ssh_private_key_file = null
    ssh_private_key      = tls_private_key.admin.private_key_openssh
    instance_token       = google_compute_instance.this.self_link
  }
}

# --- Testing-only outputs ------------------------------------------------
# Expose the rendered ssh-keys metadata string and cloud-init user-data so
# terraform tests can assert on the exact values fed into the instance,
# unaffected by lifecycle.ignore_changes on the instance resource.
output "test_ssh_keys_metadata" {
  description = "Internal: rendered GCE ssh-keys metadata string. Testing use only."
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
