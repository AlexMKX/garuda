# ensure_docker_image

`ensure_docker_image` is the shared helper for controller-built Docker image delivery.

- Builds the image on the controller from `ensure_docker_image_build_path`.
- Transfers and loads the image on the target only when target digest is missing or stale.
- Owns target-side stable-tag assignment by retagging the delivered digest to the requested name (for example `repo:latest`) and asserting digest parity.
- Exports `ensure_docker_image_delivered_image_ref` and `ensure_docker_image_delivered_manifest_digest` for observability, debugging, and downstream checks.

## Contract for current and future roles

- Roles that need controller-built Docker image delivery must use `ensure_docker_image`.
- Compose/runtime wiring must keep using stable tags (for example `:latest`) instead of digest-ref env plumbing.
- Do not introduce bespoke `build -> save -> copy -> load` pipelines when this helper fits the workload.
