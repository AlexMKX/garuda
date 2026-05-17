output "connection_data" {
  description = "Passthrough of compute-host connection_data; consumed by the smoke playbook."
  value       = module.host.connection_data
  sensitive   = true
}

output "host_public_ipv4" {
  description = "Public IPv4 of the validation host."
  value       = module.host.public_ipv4
}

output "ansible_smoke_inventory" {
  description = <<EOT
Ansible inventory snippet for modules/k3s_cloud_init/tests/smoke/k3s_z2g.yml.
One host under group 'k3s_validation', wired with the module-generated
SSH key. Mirrors the shape used by examples/mini-site/garuda/outputs.tf.
EOT
  sensitive   = true
  value = {
    k3s_yc = {
      ansible_host                 = module.host.public_ipv4
      ansible_user                 = module.host.connection_data.user
      ansible_ssh_private_key_file = null
      ansible_ssh_private_key      = module.host.connection_data.ssh_private_key
    }
  }
}
