# Ansible Role: wireguard

Deploy WireGuard mesh networks with optional keepalived HA and Docker Compose integration.

This role manages WireGuard tunnel configuration and optional keepalived for HA failover.
It does **not** manage FRR, OSPF, or route distribution — those belong to the `routing` role.

## Features

- [OK] **WireGuard mesh generation** - Automatic peer configuration and key management
- [OK] **High Availability** - Keepalived for automatic failover (optional)
- [OK] **Docker integration** - Runs in Docker containers with host or bridge networking
- [OK] **Policy routing** - Selective traffic steering with fwmark and ip rules
- [OK] **Border routing** - NAT and default route injection for edge nodes

## Requirements

- Ansible >= 2.15
- Docker / Docker Compose on target hosts
- Python >= 3.9
- geerlingguy.docker role (for Docker installation)

## Role Variables

### Required Variables

#### For `generate_config` mode:

```yaml
wireguard_mode: generate_config
wireguard_tunnel_name: "my_tunnel"          # Unique identifier (1-15 chars)
wireguard_target_hosts: "mesh_nodes"        # Inventory group
wireguard_tunnel_config:                    # Tunnel configuration
  name: "my_tunnel"
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

#### For `apply_config` mode:

```yaml
wireguard_mode: apply_config
wireguard_mesh_config: "{{ generated_config }}"  # From generate_config step
```

### Optional Variables

```yaml
# Directory paths
wireguard_mesh_root: /opt/mesh              # Base directory for configs
wireguard_ops_root: /opt/mesh/ops           # Build contexts

# Cleanup options
wireguard_cleanup_remove_ops: false         # Remove build contexts on cleanup
```

### Host-specific Configuration

```yaml
hosts:
  node-name:
    # Network configuration
    network_config:
      network_mode: "host"                  # Docker network mode (host/bridge)
    
    # WireGuard settings
    expose: "10.0.1.10:51820"               # Listen address:port
    table: "off"                            # Disable wg-quick routing
    uplink_interface: "eth0"                # Internet-facing interface
    transit_mark: 100                       # fwmark for policy routing
    
    # Border router settings
    border: true                            # Enable NAT and default routes
```

## Dependencies

- `geerlingguy.docker` - For Docker installation
- `community.docker` collection - For docker_compose_v2 module

Install dependencies:

```bash
ansible-galaxy role install geerlingguy.docker
ansible-galaxy collection install community.docker
```

## Example Playbook

See [example-mesh-deployment.yml](docs/example-mesh-deployment.yml) for a complete example.

### Quick Example

```yaml
---
- name: "Generate mesh configuration"
  hosts: localhost
  gather_facts: false
  
  vars:
    wireguard_tunnel_name: "my_mesh"
    mesh_config:
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
  
  tasks:
    - name: "Set common variables"
      ansible.builtin.set_fact:
        wireguard_tunnel_name: "{{ wireguard_tunnel_name }}"
        wireguard_mesh_configs: {}
    
    - name: "Generate mesh configuration"
      ansible.builtin.include_role:
        name: wireguard
        tasks_from: generate_config
      vars:
        wireguard_mode: generate_config
        wireguard_target_hosts: mesh_nodes
        wireguard_tunnel_config: "{{ mesh_config }}"

- name: "Deploy mesh"
  hosts: mesh_nodes
  become: true
  
  tasks:
    - name: "Apply configuration"
      ansible.builtin.include_role:
        name: wireguard
        tasks_from: apply_config
      vars:
        wireguard_mode: apply_config
        wireguard_mesh_config: "{{ hostvars['localhost']['wireguard_mesh_configs']['my_mesh'] }}"
    
    - name: "Start containers"
      community.docker.docker_compose_v2:
        project_src: "{{ wireguard_compose_project }}"
        build: always
        state: present
```

## Usage

### 1. Normal deployment

```bash
ansible-playbook -i inventory.yml deploy-mesh.yml
```

### 2. With cleanup

```bash
ansible-playbook -i inventory.yml deploy-mesh.yml --tags cleanup
```

### 3. Fresh install

```bash
ansible-playbook -i inventory.yml deploy-mesh.yml --tags fresh-install
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Node A (10.0.1.10)                                     │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Docker Host Network                            │   │
│  │  ┌──────────────┐  ┌───────────┐               │   │
│  │  │  WireGuard   │  │ Keepalived│               │   │
│  │  │  wg0: .1/30  │  │    HA     │               │   │
│  │  └──────────────┘  └───────────┘               │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                            │
                            │ WireGuard tunnel
                            │ 10.200.10.0/30
                            │
┌─────────────────────────────────────────────────────────┐
│  Node B (203.0.113.50) - Border Router                 │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Docker Bridge Network                          │   │
│  │  ┌──────────────┐  ┌───────────┐               │   │
│  │  │  WireGuard   │  │ Keepalived│               │   │
│  │  │  wg0: .2/30  │  │    NAT    │               │   │
│  │  └──────────────┘  └───────────┘               │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                            │
                            │ Internet
                            ▼
```

## Components

### WireGuard
- Encrypted tunnel between nodes
- Automatic key generation and management
- Configurable AllowedIPs and routing

### Keepalived (optional)
- Health monitoring
- Automatic failover
- nftables integration for border routing

> **Note:** FRR/OSPF and route distribution are managed by the `routing` role, not this role.

## Management

### Check status

```bash
docker compose -f /opt/mesh/my_mesh/docker-compose.yml ps
```

### View logs

```bash
docker compose -f /opt/mesh/my_mesh/docker-compose.yml logs -f
```

### Restart services

```bash
docker compose -f /opt/mesh/my_mesh/docker-compose.yml restart
```

### WireGuard status

```bash
docker exec my_mesh-my_mesh-1 wg show
```

## Troubleshooting

### Containers not starting

Check Docker logs:
```bash
docker compose -f /opt/mesh/my_mesh/docker-compose.yml logs
```

### No connectivity

Check WireGuard handshake:
```bash
docker exec my_mesh-my_mesh-1 wg show
```

## License

GPL-2.0-or-later

## Author

Alexander K <ansible@example.com>

