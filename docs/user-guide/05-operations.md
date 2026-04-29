# 5. Operations

## Prerequisites

- Terraform 1.14 or newer.
- Ansible plus project collection requirements:
  `ansible-galaxy install -r requirements.yml` (if present).
- SSH access to every target host with the key referenced in
  `host_facts.*.inventory.ansible_ssh_private_key_file`.
- Python virtualenv for running the behavioural test suite (the
  repository keeps one at `venv3.13/`).
- Docker engine on every Linux target; it is installed automatically
  by `roles/linux_host_prerequisites` on the first apply.

## First-time deploy

```bash
cd dev/vpn2
terraform init
terraform apply
```

Known first-run caveat: the Firezone OIDC module depends on a live
Firezone API token, and the token's payload path only becomes stable
after Firezone itself has been deployed once. Work around it with a
two-pass apply:

```bash
terraform apply -auto-approve \
  -target module.firezone_main \
  -target module.firezone_api_token_rnd

terraform apply -auto-approve
```

After that, subsequent applies are single-pass.

## Final verification

Per `AGENTS.md`, final end-to-end verification runs through:

```bash
ansible-playbook dev/vpn2/smoke/z2g.yml
```

`z2g` is the smoke playbook that checks the topology is converged,
transit routing works, and Firezone responds.

## Update flow

- Change Terraform code and run `terraform plan` before `apply`.
- Changing an Ansible role under `roles/` also triggers a re-apply:
  `modules/linux_apply` hashes role sources and, on drift, replaces
  its `terraform_data.runtime` resource, which re-invokes the
  playbook on the host.
- For RouterOS changes touch the relevant resources or the
  `modules/wireguard/routeros` inputs and apply again.

## Destroy

```bash
terraform -chdir=dev/vpn2 destroy
```

Or run the orderly playbook:

```bash
ansible-playbook dev/vpn2/destroy.yml
```

The backbone operator removes its own sidecars on shutdown as part of
the reconcile loop.

## RouterOS DHCP drift reconcile

RouterOS's DHCP client occasionally rewrites
`default-route-tables` in a way that breaks the `wg_bypass` route.
Reconcile it from a workstation without a full `apply`:

```bash
ansible-playbook dev/vpn2/reconcile_routeros.yml -e reconcile_task=dhcp
```

## Testing

- Behaviour and contract tests:
  ```bash
  pytest tests/
  ```
- Module-local Terraform tests:
  ```bash
  terraform -chdir=modules/<name> test
  ```
- Post-apply live probes:
  ```bash
  ansible-playbook playbooks/healthcheck_topology.yml
  ```

## Adding a new workload

High-level steps. For the FRR label and sidecar contract, see
[`frr_injector/README.md`](../../roles/backbone_network/files/ospf_injector/frr_injector/README.md).

1. Write an Ansible role that renders a Docker compose stack for the
   new workload, attached to `backbone_network` and (optionally)
   `border_network`.
2. Write a thin Terraform module that wraps `modules/linux_apply` and
   passes the role's `name`, variables, and `connection_data`.
3. Tag the container with the appropriate labels
   (`garuda.frr.ospf.enabled`, `garuda.frr.ospf.router_id`, etc.)
   so the backbone operator will attach an FRR sidecar.
4. Wire the module into `dev/vpn2/main.tf` with `depends_on =
   [module.backbone_network_main]`.

## Troubleshooting

| Symptom                                         | First command                                                      |
|-------------------------------------------------|--------------------------------------------------------------------|
| Backbone operator does not become ready         | `docker logs garuda-backbone-operator` on the host                 |
| OSPF neighbor does not come up                  | `docker exec <sidecar> vtysh -c 'show ip ospf neighbor'`           |
| Transit route missing on a consumer             | `docker exec <consumer> ip route show table 10000`                 |
| Firezone returns 401 during `terraform apply`   | See the Firezone OIDC module README and the two-pass apply above   |
| RouterOS cannot reach tunnel endpoint        | Run the DHCP reconcile playbook above                              |

## Observability and logs

- Docker log driver is `json-file`, `max-file=5`, `max-size=100m`,
  applied by `roles/linux_host_prerequisites`.
- FRR state is inspected with `vtysh -c '...'` inside the sidecar.
- `ipt_server` logs to stdout; follow with
  `docker logs -f <ipt_server-container>`.
- The backbone operator exposes its health at
  `127.0.0.1:8080/health` on the operator container.
