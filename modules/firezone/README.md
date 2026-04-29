# firezone

Workload-centric Terraform module for one Firezone deployment on one Linux host.

Why:

- keeps Firezone-specific inputs explicit at the environment layer
- avoids leaking generic config maps into Terraform composition code

Inputs:

- `name`
- `host_name`
- `firezone_dir`
- `server_url`
- `admin_password`
- `client_subnet`
- `host_networking`
- `uplink_interface`

Outputs:

- `firezone_dir` - effective Firezone compose directory returned by the workload

Behavior:

- renders the Firezone role payload expected by the shared executor
- applies and destroys the workload through `modules/linux_apply`
