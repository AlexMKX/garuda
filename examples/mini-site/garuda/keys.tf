# Write SSH private keys to local files so Ansible smoke can reference them
# via ansible_ssh_private_key_file. Keys are derived from connection_data
# outputs of infra/; they rotate only when VMs are recreated.
# When ssh_private_key is null (token-based auth), the file is written with a
# placeholder so the resource remains valid; the actual path is unused in that case.

locals {
  _key_dir = abspath("${path.module}/.keys")
}

resource "local_sensitive_file" "ssh_key_hub" {
  filename        = "${local._key_dir}/hub.pem"
  content         = coalesce(var.connection_data_hub.ssh_private_key, " ")
  file_permission = "0600"
}

resource "local_sensitive_file" "ssh_key_edges" {
  # Use keys(var.edges) to avoid for_each on a sensitive map.
  # var.edges is not sensitive; var.connection_data_edges is.
  for_each = var.edges

  filename        = "${local._key_dir}/${each.key}.pem"
  content         = coalesce(var.connection_data_edges[each.key].ssh_private_key, " ")
  file_permission = "0600"
}
