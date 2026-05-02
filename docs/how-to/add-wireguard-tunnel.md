# How to Add a WireGuard Tunnel

Garuda supports two tunnel types with different wiring:

1. **Linux-to-Linux** — hub to egress peer or any Linux node.
2. **Linux-to-RouterOS** — hub to a RouterOS device (branch LAN).

## Linux-to-Linux tunnel

Three modules work together:

| Module              | Role                                              |
|---------------------|---------------------------------------------------|
| `wireguard/tunnel`  | Generates keys and exports per-peer config        |
| `wireguard/linux`   | Deploys the WireGuard container on a Linux host   |
| `wireguard/linux`   | (second call) Deploys the other side              |

### Step 1: Define the tunnel (key generation)

```hcl
module "wireguard_tunnel_eur" {
  source   = "../../modules/wireguard/tunnel"
  name     = "eur"
  env_slug = var.env_slug
  subnet   = "192.0.2.16/28"
  peers = {
    hub = {
      address   = "192.0.2.17"
      listen_port = 51820
    }
    edge = {
      address       = "192.0.2.18"
      listen_port   = 51820
      endpoint_host = "eur.example.net"
    }
  }
}
```

`wireguard/tunnel` emits two name fields per peer:

- `tunnel_name = "${env_slug}-eur"` — env-prefixed. Used by `wireguard/routeros`.
- `kernel_ifname = "eur"` — raw (max 15 chars). Used by `wireguard/linux` as the
  Linux kernel interface name.

### Step 2: Deploy hub side

```hcl
module "wireguard_linux_eur_hub" {
  source         = "../../modules/wireguard/linux"
  host_name      = "hub"
  config         = module.wireguard_tunnel_eur.peers["hub"]
  peer           = module.wireguard_tunnel_eur.peers["edge"]
  allowed_nets   = [module.wireguard_tunnel_eur.peers["edge"].subnet]
  table          = "off"
  connection_data = var.connection_data_hub
  nic_attach     = ["backbone", "border"]
  labels         = { /* OSPF labels */ }
  depends_on     = [module.backbone_network["hub"]]
}
```

### Step 3: Deploy edge side

```hcl
module "wireguard_linux_eur_edge" {
  source         = "../../modules/wireguard/linux"
  host_name      = "eur"
  config         = module.wireguard_tunnel_eur.peers["edge"]
  peer           = module.wireguard_tunnel_eur.peers["hub"]
  allowed_nets   = ["0.0.0.0/0"]
  table          = "off"
  connection_data = var.connection_data_edges["eur"]
  nic_attach     = ["backbone", "border"]
  labels         = { /* OSPF labels with default_originate=true */ }
  depends_on     = [module.backbone_network["eur"]]
}
```

The edge side sets `garuda.frr.ospf.default_originate = "true"` so it originates
the default route into OSPF.

## Linux-to-RouterOS tunnel

Three modules work together:

| Module              | Role                                                        |
|---------------------|-------------------------------------------------------------|
| `wireguard/tunnel`  | Generates keys and exports per-peer config                  |
| `wireguard/linux`   | Deploys the WireGuard container on the hub (Linux side)     |
| `wireguard/routeros`| Deploys the WireGuard interface and OSPF on RouterOS        |

### Key difference: tunnel_name vs kernel_ifname

- `wireguard/linux` consumes `kernel_ifname` (raw, no env prefix) as the Linux
  kernel interface name.
- `wireguard/routeros` consumes `tunnel_name` (env-prefixed) for all RouterOS
  resource names to prevent collisions on shared devices.

Both fields come from the same `wireguard/tunnel` output — pass the same `peers[...]`
object to each module.

### Step 1: Define the tunnel

Same as Linux-to-Linux, but add `endpoint_host` on the RouterOS side so the hub
can initiate the connection:

```hcl
module "wireguard_tunnel_ros" {
  source   = "../../modules/wireguard/tunnel"
  name     = "ros"
  env_slug = var.env_slug
  subnet   = "198.51.100.0/28"
  peers = {
    hub = {
      address     = "198.51.100.1"
      listen_port = 51821
      endpoint_host = "hub.example.net"
    }
    ros = {
      address     = "198.51.100.2"
      listen_port = 51821
    }
  }
}
```

### Step 2: Deploy hub side (Linux)

```hcl
module "wireguard_linux_ros_hub" {
  source         = "../../modules/wireguard/linux"
  host_name      = "hub"
  config         = module.wireguard_tunnel_ros.peers["hub"]
  peer           = module.wireguard_tunnel_ros.peers["ros"]
  # ...
  depends_on     = [module.backbone_network["hub"]]
}
```

### Step 3: Deploy RouterOS side

```hcl
module "wireguard_routeros_ros" {
  source       = "../../modules/wireguard/routeros"
  hostname     = var.routeros.hostname
  config       = module.wireguard_tunnel_ros.peers["ros"]
  peer         = module.wireguard_tunnel_ros.peers["hub"]
  subnet       = module.wireguard_tunnel_ros.peers["ros"].subnet
  allowed_nets = ["0.0.0.0/0"]
  router_id    = var.hub_ros.ospf_router_id_peer
}
```

RouterOS resource names will be prefixed with `env_slug` (e.g. `prod-ros`).

## Further reading

- [`wireguard/tunnel` README](../../modules/wireguard/tunnel/README.md)
- [`wireguard/linux` README](../../modules/wireguard/linux/README.md)
- [`wireguard/routeros` README](../../modules/wireguard/routeros/README.md)
- [Architecture — WireGuard naming split](../concepts/architecture.md#wireguard-tunnel-naming-split)
