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

```bash
cd dev/vpn2
terraform init
terraform apply
```

For first-run caveats (Firezone OIDC two-pass apply) see the
[operations guide](docs/user-guide/05-operations.md#first-time-deploy).

## Documentation map

User-facing:

1. [Overview — what Garuda is and why](docs/user-guide/01-overview.md)
2. [Architecture — components and their roles](docs/user-guide/02-architecture.md)
3. [Runtime processes — failover, OSPF, transit, health](docs/user-guide/03-processes.md)
4. [Three-node example walkthrough (`dev/vpn2`)](docs/user-guide/04-example-dev-vpn2.md)
5. [Operations — deploy, verify, update, destroy, troubleshoot](docs/user-guide/05-operations.md)

Component-level contracts:

- [Backbone operator overview](roles/backbone_network/files/ospf_injector/README.md)
- [FRR injector runtime contract](roles/backbone_network/files/ospf_injector/frr_injector/README.md)
- [Transit concept](roles/backbone_network/files/ospf_injector/frr_injector/transit.md)
- [Network manager runtime contract](roles/backbone_network/files/ospf_injector/network_manager/README.md)
- [Sidecar operator runtime contract](roles/backbone_network/files/ospf_injector/sidecar_operator/README.md)
- [FRR sidecar runtime contract](roles/backbone_network/files/frr_sidecar/README.md)
- [ipt_server task layer](roles/ipt_server/files/ipt-server/tasks/README.md)
- Terraform modules: see `modules/<name>/README.md`

## `dev/vpn2` verification

- [Verification checklist](dev/vpn2/checklist.md)
- Final smoke: `ansible-playbook dev/vpn2/smoke/z2g.yml` (see `AGENTS.md`).
