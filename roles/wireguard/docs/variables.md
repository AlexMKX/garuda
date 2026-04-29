# WireGuard Role Variables

Complete reference for all variables used in the `alexmkx.garuda.wireguard` role.

## Table of Contents

- [Required Variables](#required-variables)
- [Optional Variables](#optional-variables)
- [Host Configuration](#host-configuration)
- [Advanced Options](#advanced-options)

---

## Required Variables

### `wireguard_mode`

**Type:** `string`  
**Required:** Yes  
**Choices:** `generate_config`, `apply_config`

Operating mode for the role:
- `generate_config` - Generate mesh configuration on localhost
- `apply_config` - Apply configuration to target hosts

**Example:**
```yaml
wireguard_mode: generate_config
```

---

### `wireguard_tunnel_name`

**Type:** `string`  
**Required:** Yes  
**Length:** 1-15 characters

Unique identifier for the tunnel. Used as:
- Docker container name prefix
- Configuration directory name
- WireGuard interface name

**Example:**
```yaml
wireguard_tunnel_name: "my_mesh"
```

---

### `wireguard_target_hosts`

**Type:** `string`  
**Required:** Yes (for `generate_config` mode)

Ansible inventory group containing target hosts for the mesh.

**Example:**
```yaml
wireguard_target_hosts: "mesh_nodes"
```

---

### `wireguard_tunnel_config`

**Type:** `dict`  
**Required:** Yes (for `generate_config` mode)

Tunnel configuration dictionary.

**Structure:**
```yaml
wireguard_tunnel_config:
  name: "tunnel_name"           # Must match wireguard_tunnel_name
  subnet: "10.200.10.0/30"      # Point-to-point subnet
  hosts:                        # Host configurations
    node-a:
      # ... host config
    node-b:
      # ... host config
```

**Example:**
```yaml
wireguard_tunnel_config:
  name: "my_mesh"
  subnet: "10.200.10.0/30"
  hosts:
    node-a:
      expose: "10.0.1.10:51820"
      table: "off"
    node-b:
      expose: "203.0.113.50:51820"
      table: "off"
      border: true
```

---

### `wireguard_mesh_config`

**Type:** `dict`  
**Required:** Yes (for `apply_config` mode)

Generated mesh configuration from `generate_config` step.

**Example:**
```yaml
wireguard_mesh_config: "{{ hostvars['localhost']['wireguard_mesh_configs']['my_mesh'] }}"
```

---

## Optional Variables

### `wireguard_mesh_root`

**Type:** `string`  
**Default:** `/opt/mesh`

Base directory for mesh configurations on target hosts.

**Example:**
```yaml
wireguard_mesh_root: /opt/mesh
```

---

### `wireguard_ops_root`

**Type:** `string`  
**Default:** `/opt/mesh/ops`

Directory for Docker build contexts (Dockerfiles, scripts).

**Example:**
```yaml
wireguard_ops_root: /opt/mesh/ops
```

---

### `wireguard_cleanup_remove_ops`

**Type:** `boolean`  
**Default:** `false`

Whether to remove build contexts during cleanup.

**Example:**
```yaml
wireguard_cleanup_remove_ops: true
```

---

## Host Configuration

Each host in `wireguard_tunnel_config.hosts` can have the following parameters:

### `expose`

**Type:** `string`  
**Required:** Yes

WireGuard listen address and port.

**Format:** `IP:PORT` or `PORT` (for bridge network)

**Examples:**
```yaml
expose: "10.0.1.10:51820"      # Host network with specific IP
expose: "203.0.113.50:51820"   # Public IP
expose: "51820"                # Bridge network (Docker assigns IP)
```

---

### `table`

**Type:** `string`  
**Required:** Yes  
**Default:** `"off"`

WireGuard routing table mode. Set to `"off"` to disable wg-quick automatic routing.

**Example:**
```yaml
table: "off"
```

---

### `network_config`

**Type:** `dict`  
**Required:** No

Docker network configuration for the container.

**Options:**
```yaml
network_config:
  network_mode: "host"          # Docker network mode: "host" or "bridge"
```

**Example:**
```yaml
network_config:
  network_mode: "host"
```

---

### `uplink_interface`

**Type:** `string`  
**Required:** No (required for host network mode)

Physical network interface for internet connectivity.

**Example:**
```yaml
uplink_interface: "eth0"
```

---

### `transit_mark`

**Type:** `integer`  
**Required:** No

Firewall mark (fwmark) for policy routing. Used with ip rules and routing tables.

**Example:**
```yaml
transit_mark: 100
```

---

### `border`

**Type:** `boolean`  
**Default:** `false`

Mark host as border router. Enables:
- NAT (masquerade) via nftables
- Default route injection via keepalived
- Border router functionality

**Example:**
```yaml
border: true
```

---

## Advanced Options

### Custom AllowedIPs

By default, WireGuard peers use `0.0.0.0/0` for full mesh connectivity. You can customize this in the generated configuration.

### Custom Keepalived Scripts

Keepalived uses custom scripts for:
- `notify_master.sh` - Becomes MASTER (enables NAT)
- `notify_backup.sh` - Becomes BACKUP (disables NAT)
- `notify_fault.sh` - Detects FAULT (disables NAT)

Scripts are located in `roles/wireguard/files/keepalived/`.

---

## Variable Precedence

1. Play variables (highest priority)
2. Host variables from inventory
3. Group variables from inventory
4. Role defaults (lowest priority)

---

## Examples

### Simple mesh with two nodes

```yaml
wireguard_tunnel_config:
  name: "simple_mesh"
  subnet: "10.200.10.0/30"
  hosts:
    node-a:
      expose: "10.0.1.10:51820"
      table: "off"
    node-b:
      expose: "203.0.113.50:51820"
      table: "off"
```

### Host network with border router

```yaml
wireguard_tunnel_config:
  name: "host_mesh"
  subnet: "10.200.20.0/30"
  hosts:
    internal-node:
      network_config:
        network_mode: "host"
      expose: "192.168.1.10:51820"
      table: "off"
      uplink_interface: "eth0"
      transit_mark: 100
    
    border-node:
      expose: "203.0.113.50:51820"
      table: "off"
      border: true
```

### Multiple peers

```yaml
wireguard_tunnel_config:
  name: "multi_mesh"
  subnet: "10.200.30.0/29"      # /29 for up to 6 hosts
  hosts:
    hub:
      expose: "203.0.113.10:51820"
      table: "off"
      border: true
    
    spoke-1:
      expose: "10.0.1.10:51820"
      table: "off"
    
    spoke-2:
      expose: "10.0.2.10:51820"
      table: "off"
```

---

## See Also

- [Example Playbook](example-mesh-deployment.yml)
- [Example Inventory](example-inventory.yml)
- [Role README](../README.md)

