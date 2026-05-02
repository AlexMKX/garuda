# Prerequisites

## Required CLI tools

| Tool                            | Purpose                                                   |
|---------------------------------|-----------------------------------------------------------|
| Terragrunt                      | Orchestrate multi-unit OpenTofu stacks                    |
| OpenTofu (or Terraform >= 1.6)  | Provision infrastructure and run Ansible via `linux_apply`|
| Ansible >= 2.15                 | Apply roles to target hosts                               |
| SOPS + age                      | Decrypt secrets in SOPS-encrypted `inputs.tfvars.yaml`    |
| Docker (controller)             | Required only in `build` mode (see below)                 |

## Cloud credentials

You need credentials for the cloud providers that host your compute. The
`yc_compute_host` and `gcp_compute_host` modules each accept a `connection_data`
output that includes the provisioned instance's SSH host, user, and key. See
[connection_data contract](../reference/connection-data.md).

## SSH key delivery

SSH keys are declared in `operator_ssh_keys` and injected by compute modules.
`connection_data.instance_token` is an opaque token populated by the compute
module from the cloud instance identity; you do not set it manually. It signals
`linux_apply` when a VM has been recreated so Ansible re-applies automatically.

## Image source: pull (clients) vs build (developers)

Garuda workloads run as Docker containers. The `ensure_docker_image` role
delivers images in one of two modes, selected by the `GARUDA_IMAGE_SOURCE`
environment variable on the controller:

| Mode    | Behaviour                                                                              | When to use         |
|---------|----------------------------------------------------------------------------------------|---------------------|
| `pull`  | Target host pulls pre-built images from `ghcr.io/alexmkx/garuda-*` and retags them.  | End users (clients) |
| `build` | Controller builds each image from `roles/<role>/files/<image>/` and ships a tar archive via Ansible. | Developers, CI |

```bash
export GARUDA_IMAGE_SOURCE=pull   # or 'build'
```

If `GARUDA_IMAGE_SOURCE` is unset, the role defaults to `build`. This is
deliberate — a forgotten variable must not silently replace local Dockerfile
changes with a stale registry image. Clients must set `pull` explicitly.

`pull` mode does not require Docker on the controller; the target host does the
work. `build` mode requires a working `docker` daemon and a clone of the
garuda-repo source tree on the controller.

## Further reading

- [Reference topology](reference-topology.md) — in-repo mini-site walkthrough.
- [connection_data contract](../reference/connection-data.md)
