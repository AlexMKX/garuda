# Testing Runbook

## Run all non-live tests

```bash
# Operator unit tests
pytest tests/

# Module contract tests
tofu -chdir=modules/linux_apply test
tofu -chdir=modules/ipt_server test
tofu -chdir=modules/wireguard/tunnel test
tofu -chdir=modules/wireguard/linux test
tofu -chdir=modules/wireguard/routeros test
tofu -chdir=modules/firezone test
tofu -chdir=modules/yc_compute_host test
tofu -chdir=modules/gcp_compute_host test
```

## Run live smoke

After a successful apply:

```bash
cd examples/mini-site/smoke
ansible-playbook z2g.yml
```

`z2g.yml` is the intended public entrypoint, but it is not wired in the repository
yet. See `examples/mini-site/smoke/README.md` for the expected checks.

## Post-apply health check

Use the smoke playbook once it exists. The repository does not currently ship a
separate topology health-check playbook wrapper.

## Further reading

- [Testing reference](../reference/testing.md) — full layer description.
- [Smoke testing](smoke-testing.md) — what smoke tests cover.
