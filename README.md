# Garuda

```
                                                                                                    
                                                         
                                       -.    =           
                                 :.    -*:  =+.          
                                 :-:   =** :--.          
    :- -                          ==:  +** =-:   :+.     
    -+:*.                         ==:  #**-=-:  ==:      
    -+#+:*= +               .=:   -==:=#**=-=.==-.       
  :+++%***=+-                .-:- ---:#**==*==-=. .-:    
   ***#**+#*+=:               :-:.=-+**#*-=-=**#*++=:.   
   ++******+=-::.             :--*+-+*###**#**+*****+.   
   .**+*+++=*-==-.            .+---==*##*+********#*++   
    =+=++*-+==--***:         ==-=***###*******++++++:    
     =-=+-:++=**=-=+=      --==+*=--+=-=+***********-    
     ==::--**++=+**=+*=    -=***+==+****+++***+*++==.    
      =*===-+++********+. :==+++===+===+*********-       
        .*+====+*****+**===########===#*++***++***-      
           =+==+++****#+=+*#%#***++++=-+*#*+++===        
             :*==+*#+--+*##%####*********+-=*-.          
            .---=*==*S*C#R%E%#W*###******#*=.            
          ::*%%##C**E#N%S%O%RSH++****IP*+++.             
             +*###%%%%#*#*##%%##*--+**++*-               
               .+**%##########%#**+++=:.                 
                   ::#*#####%%####++*%#**++++=.          
                         *%%%*#%##+==+*#####%%%%%%.      
                          :*#- +++****++++***###*++=     
                            -=+:+=+###***+=++***##:      
                             .  .=+*######*++=+*+-:      
                                 -=++###%*##+**+*+       
                                  :=+++###=+##+          
                                    :+=+*++              
                                                                           
                                                                                                    
```

Garuda (**G**eo-distributed **A**utonomous **R**outing **U**nderlay for **D**eclarative **A**ccess) is a declarative platform for a geo-distributed VPN
mesh. Like its mythological namesake — the swift, world-spanning avian mount of Hindu mythology — Garuda transports traffic across isolated realms and boundaries.

It composes VPN tunnels, access portals (like Firezone), egress gateways, and
RouterOS devices into one topology with a shared routing plan and
automatic failover driven by OSPF. Workloads are instrumented by a
label-driven operator, so new VPN services can be added without
changing the operator itself.

## Key use-cases

- **Mesh with failover** between branches, data centers, and
  individual servers.
- **Geo and domain based traffic distribution** (for example: `RU`
  traffic stays local, everything else exits through a foreign
  egress).
- **End-user access** through self-service portals (currently Firezone).
- **Platform for arbitrary VPN services**: onboard new workloads by
  adding an Ansible role, a Terraform wrapper, and a few Docker
  labels.

Everything is deployed declaratively — no ad-hoc scripts, no GUI
configuration.

## Quickstart

The public example is a sanitized mini-site template; copy it before adding real
cloud IDs or secrets. The `examples/mini-site` tree currently documents the
expected layout; add the Terragrunt/OpenTofu files before running `terragrunt`
commands.

```bash
cd examples/mini-site/infra
terragrunt apply

cd ../garuda
terragrunt apply

cd ../smoke
ansible-playbook z2g.yml
```

The `smoke/` directory describes the expected `z2g.yml` entrypoint. Wire the
playbook before using this example for live verification.

For first-run caveats (Firezone OIDC two-pass apply) see the
[deploy guide](docs/operations/deploy-update-destroy.md#first-time-deploy).

## Image source: pull (clients) vs build (developers)

`garuda` workloads run as Docker containers. The `ensure_docker_image`
role delivers each image to its target host in one of two modes,
selected by the `GARUDA_IMAGE_SOURCE` environment variable on the
machine that runs `terraform`/`terragrunt`:

| Mode    | Behaviour                                                                                              | When to use            |
| ------- | ------------------------------------------------------------------------------------------------------ | ---------------------- |
| `pull`  | The target pulls pre-built images from `ghcr.io/alexmkx/garuda-*` and retags them to the local stable tag. | End users (clients).   |
| `build` | The controller builds each image from sources in `roles/<role>/files/<image>/`, then ships a tar archive to the target via Ansible. | Developers, CI.        |

Set the variable once before `terraform apply`:

```bash
export GARUDA_IMAGE_SOURCE=pull   # or 'build'
```

If `GARUDA_IMAGE_SOURCE` is unset the role defaults to `build`. This is
deliberate — a forgotten env var must not silently replace local
Dockerfile changes with a stale `:latest` from the registry. Clients
must set `pull` explicitly.

`pull` mode does not require Docker on the controller; the target does
the work. `build` mode requires a working `docker` daemon and a clone of
the garuda-repo source tree on the controller.

## Documentation map

Concepts:

1. [Overview — what Garuda is and why](docs/concepts/overview.md)
2. [Architecture — components and their roles](docs/concepts/architecture.md)
3. [Routing model — OSPF, transit, PBR, pinning](docs/concepts/routing-model.md)

Getting started:

4. [Prerequisites — tools and credentials](docs/getting-started/prerequisites.md)
5. [Reference topology — mini-site walkthrough](docs/getting-started/reference-topology.md)
6. [First deploy](docs/getting-started/first-deploy.md)

How-to:

7. [Define routing policy](docs/how-to/define-routing-policy.md)
8. [Add a Linux egress](docs/how-to/add-linux-egress.md)
9. [Add a WireGuard tunnel](docs/how-to/add-wireguard-tunnel.md)
10. [Add a workload](docs/how-to/add-workload.md)

Operations:

- [Troubleshooting](docs/operations/troubleshooting.md)
- [Smoke testing](docs/operations/smoke-testing.md)
- [Deploy / update / destroy](docs/operations/deploy-update-destroy.md)

Reference:

- [Module index](docs/reference/modules.md)
- [Label taxonomy](docs/reference/labels.md)
- [connection_data contract](docs/reference/connection-data.md)
- [Routing policy schema](docs/reference/routing-policy.md)

Component-level contracts:

- [Backbone operator overview](roles/backbone_network/files/ospf_injector/README.md)
- [FRR injector runtime contract](roles/backbone_network/files/ospf_injector/frr_injector/README.md)
- [Transit concept](roles/backbone_network/files/ospf_injector/frr_injector/transit.md)
- [Network manager runtime contract](roles/backbone_network/files/ospf_injector/network_manager/README.md)
- [Sidecar operator runtime contract](roles/backbone_network/files/ospf_injector/sidecar_operator/README.md)
- [FRR sidecar runtime contract](roles/backbone_network/files/frr_sidecar/README.md)
- [ipt_server task layer](roles/ipt_server/files/ipt-server/tasks/README.md)
- Terraform modules: see `modules/*/README.md`
