locals {
  _install_exec_args = concat(
    [
      "server",
      "--bind-address=127.0.0.1",
      "--https-listen-port=6443",
    ],
    var.extra_flags,
  )

  _install_exec = join(" ", local._install_exec_args)

  _env_prefix = join(" ", concat(
    var.k3s_version == null ? [] : ["INSTALL_K3S_VERSION=${var.k3s_version}"],
    ["INSTALL_K3S_EXEC=\"${local._install_exec}\""],
    [for k, v in var.extra_install_env : "${k}=${v}"],
  ))

  _cloud_config = <<EOT
#cloud-config
runcmd:
  - curl -sfL ${var.install_url} | ${local._env_prefix} sh -
EOT
}
