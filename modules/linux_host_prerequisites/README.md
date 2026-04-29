# linux_host_prerequisites

Host-scoped prerequisites module for Linux nodes.

Why:

- prepares Docker and kernel networking state before higher-level workloads run
- isolates host bootstrap concerns from service-specific roles

Inputs:

- `name`
- `host_name`
- `docker_firewall_backend`
- `docker_additional_config`
- `reboot_on_change`

Behavior:

- renders a prerequisites payload
- uses `geerlingguy.docker` as the base Docker install/service/daemon layer
- configures the Docker daemon firewall backend through `docker_daemon_options`
- optionally reboots the host through the shared executor
