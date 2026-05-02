# Module Execution Model

## Chain

```
compute module
  -> connection_data (including instance_token)
  -> workload module (wireguard/linux, firezone, ipt_server, ...)
  -> linux_apply
  -> Ansible role (via local-exec)
  -> Docker Compose stack on target host
  -> Docker labels
  -> backbone operator (frr_injector)
  -> FRR sidecar container (shares netns with workload)
```

## Layers

**Compute modules** (`yc_compute_host`, `gcp_compute_host`) provision VMs and
output `connection_data`. They are responsible for:
- Creating the host.
- Injecting SSH keys.
- Populating `connection_data.instance_token` from the cloud instance ID.

**Workload modules** (`wireguard/linux`, `firezone`, `ipt_server`, ...) accept
`connection_data` and a workload-specific configuration. They:
- Render a payload (role variables) as YAML.
- Call `modules/linux_apply` with the payload and `connection_data`.

**`modules/linux_apply`** is the shared Ansible executor. It:
- Generates a minimal dynamic Ansible inventory for the target host.
- Runs the shared `playbooks/apply.yml` via `local-exec`.
- Re-runs automatically if `connection_data.instance_token` changes (VM recreated).

**Ansible roles** receive role-native variables from the payload and:
- Install prerequisites on the host.
- Render Docker Compose files.
- Run `docker compose up --wait` (blocks until healthy).
- Place Docker container labels that carry FRR and operator intent.

**Backbone operator** (running as a container on each host) watches Docker labels
and reconciles FRR sidecars. Each sidecar shares the network namespace of its
target workload container.

## Dependency rule

Linux workload modules must declare exactly one explicit `depends_on`, and that
dependency must be the **same-host backbone module only**:

```hcl
module "wireguard_linux_usa" {
  source     = "../../modules/wireguard/linux"
  # ... inputs ...
  depends_on = [module.backbone_network["usa"]]
}
```

**Why.** `modules/linux_apply` schedules Ansible via `local-exec`. Terraform cannot
infer ordering from inside `local-exec`, so `depends_on` is the only mechanism
that serialises workload modules after the backbone is ready.

**Cross-host `depends_on` is prohibited.** It forces Terraform to track the full
output graph of the dependency and causes re-apply whenever any output of that
module changes. Use OSPF or application-level retry instead.

`linux_host_prerequisites` and `wireguard/tunnel` are transitive — they run as
roles inside the same Ansible playbook and do not need to appear in `depends_on`.

## Related

- [connection_data contract](connection-data.md)
- [Architecture — planes and node roles](../concepts/architecture.md)
