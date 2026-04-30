# ensure_docker_image

Helper role for delivering a Docker image to a target host. Two modes,
selected by the `GARUDA_IMAGE_SOURCE` env var on the controller:

| Mode    | What happens                                                                                  | Who uses it          |
| ------- | --------------------------------------------------------------------------------------------- | -------------------- |
| `pull`  | `docker pull <remote_ref>` on the target, retag to `<name>`, digest assert.                   | End users (clients). |
| `build` | Build on controller → save → copy → load on target → retag to `<name>` → digest assert.       | Developers, agent.   |

Default when the env var is unset: `build`. The default is deliberately
build-side so a developer iterating on a Dockerfile cannot have local
changes silently overridden by a stale `:latest` from `ghcr.io`. Clients
set `GARUDA_IMAGE_SOURCE=pull` once (see top-level README quickstart).

## Caller contract

The caller passes:

| Variable                              | Required when      | Meaning                                                                                  |
| ------------------------------------- | ------------------ | ---------------------------------------------------------------------------------------- |
| `ensure_docker_image_name`            | always             | Stable local tag the target compose stack references, e.g. `garuda/ipt-server:latest`.   |
| `ensure_docker_image_remote_ref`      | `pull` mode        | Full registry ref, e.g. `ghcr.io/alexmkx/garuda-ipt-server:latest`.                      |
| `ensure_docker_image_build_path`      | `build` mode       | Path to the build context on the controller.                                             |

Both `remote_ref` and `build_path` are typically passed unconditionally by
callers; the role itself decides which one is consumed based on
`ensure_docker_image_source`.

The role exports two facts for downstream observability:

- `ensure_docker_image_delivered_image_ref` — `<name>@<digest>` of the
  image after delivery.
- `ensure_docker_image_delivered_manifest_digest` — same digest, bare.

It also sets `_ensure_docker_image_needs_load` (boolean, true iff the
image on target was actually swapped this run). Caller roles key compose
recreation off this fact.

## Contract for current and future roles

- Roles that need controller-built or registry-pulled Docker image
  delivery must use `ensure_docker_image`.
- Compose/runtime wiring must keep using stable tags (for example
  `:latest`) instead of digest-ref env plumbing.
- Do not introduce bespoke `build → save → copy → load` or
  `pull → tag` pipelines when this helper fits the workload.

## Layout

```
roles/ensure_docker_image/
├── defaults/main.yml          # source default (env-driven, fallback build)
├── README.md
└── tasks/
    ├── main.yml               # validate → dispatch → finalize
    ├── validate.yml           # input contract assertions
    ├── pull.yml               # docker pull on target → retag → digest assert
    └── build.yml              # build → save → copy → load → retag → digest assert
```
