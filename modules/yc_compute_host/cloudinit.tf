# Cloud-init multipart MIME bundle. Module-managed disk-mount part is part 0
# (filename "00-attached-disks.yaml"); caller-supplied parts follow with
# filenames "10-user-0.yaml", "11-user-1.yaml", etc. Cloud-init applies parts
# sorted alphabetically by filename, so the numeric prefix is the runtime
# ordering contract.
#
# gzip=false, base64_encode=false: plaintext multipart MIME. Cloud-init on
# YC's NoCloud-style datasource accepts both; plaintext is human-readable in
# TF state and tests. Payload size << provider limit (typically 256KB).
data "cloudinit_config" "this" {
  count = local.needs_cloud_init ? 1 : 0

  gzip          = false
  base64_encode = false

  dynamic "part" {
    for_each = length(var.attached_disks) > 0 ? [1] : []
    content {
      filename     = "00-attached-disks.yaml"
      content_type = "text/cloud-config"
      content      = local._auto_user_data_part
      merge_type   = "list(append)+dict(no_replace,recurse_list)+str(append)"
    }
  }

  dynamic "part" {
    for_each = { for idx, p in var.user_data_parts : idx => p }
    content {
      filename     = "${10 + part.key}-user-${part.key}.yaml"
      content_type = "text/cloud-config"
      content      = part.value
      merge_type   = "list(append)+dict(no_replace,recurse_list)+str(append)"
    }
  }
}
