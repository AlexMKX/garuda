# connection_data Contract

The `connection_data` object is the normalized transport and authentication
contract passed from compute modules to workload modules and through to
`linux_apply`.

## Shape

```hcl
connection_data = {
  host                 = string           # SSH/management hostname or IP
  user                 = string           # SSH user
  connection           = string           # Ansible connection plugin (e.g. "ssh")
  network_os           = string           # Ansible network_os (e.g. "linux")
  password             = optional(string) # SSH password (mutually exclusive with ssh_private_key*)
  ssh_private_key_file = optional(string) # Path to private key file (mutually exclusive with password/ssh_private_key)
  ssh_private_key      = optional(string) # Inline private key PEM (mutually exclusive with ssh_private_key_file)
  instance_token       = string           # Opaque invalidation discriminator
}
```

`ssh_private_key` and `ssh_private_key_file` are mutually exclusive — provide at
most one.

## instance_token

`instance_token` is a mandatory opaque string. By convention, compute modules
populate it with a stable cloud instance identifier (Yandex Cloud
`yandex_compute_instance.id`, GCP `google_compute_instance.self_link`).

`linux_apply` treats any change to `instance_token` as a signal that the VM has
been recreated and forces a full Ansible re-apply, even if all other inputs are
unchanged. This prevents a situation where a recreated VM (with a clean filesystem)
skips Ansible because Terraform sees no diff.

Do not set `instance_token` manually unless you are writing a compute module.
Workload modules pass it through to `linux_apply` unchanged.

## Flow

```
compute module (yc_compute_host / gcp_compute_host)
  -> outputs connection_data with instance_token = cloud instance ID
  -> workload module (wireguard/linux, firezone, ipt_server, ...)
  -> linux_apply (consumes connection_data, drives Ansible)
```

## Related

- [Module execution model](module-execution-model.md)
- [`modules/linux_apply` variables](../../modules/linux_apply/README.md)
