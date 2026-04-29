#!/usr/bin/env bash
# run_linux_apply.sh — Ansible runner helper for linux_apply terraform_data provisioner.
#
# Required env vars:
#   host_name                    — inventory entry name (host_name), e.g. vpn.example.com
#   inventory_host               — actual connection address (inventory_host), IP or hostname
#   ansible_user
#   ansible_network_os
#   workload_kind
#   workload_lifecycle           — provision or destroy
#   workload_payload_b64
#   payload_hash
#   role_source_hash
#   executor_environment_hash
#   wrapper_playbook             — absolute path to apply_ansible_workload.yml
#   repo_root                    — repo root to cd into before running ansible-playbook
#
# Optional env vars:
#   ansible_connection           — default: ssh
#   ansible_password             — if non-empty, ansible_password is added to inventory
#   ansible_ssh_private_key_file — if non-empty, added to inventory as-is
#   ansible_ssh_private_key_content
#                                — if non-empty and ansible_ssh_private_key_file is empty,
#                                  content is materialized to $tmp_dir/ssh.key;
#                                  mutually exclusive with ansible_ssh_private_key_file
#   extra_hostvars               — JSON object; if non-empty and not {}, parsed and appended
#                                  as key=value pairs (extra_hostvars) to the inventory line

set -euo pipefail

# ── SSH transport reliability defaults ─────────────────────────────────────
# Ansible UNREACHABLE on transient SSH glitches breaks idempotent re-apply.
# Provide sane retry/keepalive defaults; caller env vars (e.g. terragrunt
# extra_arguments) always win — assignments below are no-ops if already set.
: "${ANSIBLE_SSH_RETRIES:=5}"
: "${ANSIBLE_TIMEOUT:=30}"
export ANSIBLE_SSH_RETRIES ANSIBLE_TIMEOUT

# Augment ANSIBLE_SSH_ARGS with keepalive options that don't already appear.
# We never replace caller-supplied flags — only append missing knobs so the
# existing host-key policy (StrictHostKeyChecking, UserKnownHostsFile, etc.)
# is preserved verbatim.
_existing_ssh_args="${ANSIBLE_SSH_ARGS:-}"
_extra_ssh_args=""
if [[ "$_existing_ssh_args" != *"ConnectTimeout="* ]]; then
  _extra_ssh_args="${_extra_ssh_args} -o ConnectTimeout=30"
fi
if [[ "$_existing_ssh_args" != *"ServerAliveInterval="* ]]; then
  _extra_ssh_args="${_extra_ssh_args} -o ServerAliveInterval=15"
fi
if [[ "$_existing_ssh_args" != *"ServerAliveCountMax="* ]]; then
  _extra_ssh_args="${_extra_ssh_args} -o ServerAliveCountMax=4"
fi
if [[ -n "$_extra_ssh_args" ]]; then
  if [[ -n "$_existing_ssh_args" ]]; then
    ANSIBLE_SSH_ARGS="${_existing_ssh_args}${_extra_ssh_args}"
  else
    ANSIBLE_SSH_ARGS="${_extra_ssh_args# }"
  fi
fi
export ANSIBLE_SSH_ARGS
unset _existing_ssh_args _extra_ssh_args

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

# ── Defaults ────────────────────────────────────────────────────────────────
ansible_connection="${ansible_connection:-ssh}"
ansible_network_os="${ansible_network_os}"
ansible_password="${ansible_password:-}"
ansible_ssh_private_key_file="${ansible_ssh_private_key_file:-}"
ansible_ssh_private_key_content="${ansible_ssh_private_key_content:-}"
extra_hostvars="${extra_hostvars:-}"
workload_result_path="${workload_result_path:-}"

# ── Materialize raw SSH key into tmp_dir (when provided) ────────────────────
# Contract: ansible_ssh_private_key_file and ansible_ssh_private_key_content
# are mutually exclusive — enforced by terraform variable validation.
# When content is provided, we write it into $tmp_dir/ssh.key (cleaned by
# the existing EXIT trap) and point ansible_ssh_private_key_file at it.
# When a path is provided, we leave it untouched — the file is owned by the
# caller and must NEVER be removed by this helper.
if [[ -n "$ansible_ssh_private_key_content" ]]; then
  if [[ -n "$ansible_ssh_private_key_file" ]]; then
    echo "ERROR: ansible_ssh_private_key_file and ansible_ssh_private_key_content are mutually exclusive" >&2
    exit 2
  fi
  (
    umask 077
    printf '%s' "$ansible_ssh_private_key_content" > "$tmp_dir/ssh.key"
  )
  ansible_ssh_private_key_file="$tmp_dir/ssh.key"
  unset ansible_ssh_private_key_content
fi

# Create result file directory and initialize a stable JSON envelope.
#
# Why: Terraform locals read this file via `fileexists()`/`file()` while
# replace operations run destroy+create provisioners. Removing the file can
# make filesystem function results flip during a single apply evaluation.
# Writing an empty envelope keeps the path stable and avoids stale outputs.
if [[ -n "${workload_result_path:-}" ]]; then
  mkdir -p "$(dirname "$workload_result_path")"
  if [[ "${workload_lifecycle}" == "provision" ]]; then
    printf '{"outputs":{}}\n' > "$workload_result_path"
  fi
fi

# ── Build inventory.ini host line ────────────────────────────────────────────
# Core transport attributes are always present. Auth attributes
# (key file, password) are added conditionally — when none are set, Ansible
# falls back to system SSH configuration (ssh-agent, ~/.ssh/config).
host_line="${host_name} ansible_host=\"${inventory_host}\" ansible_user=\"${ansible_user}\" ansible_connection=\"${ansible_connection}\" ansible_network_os=\"${ansible_network_os}\""

if [[ -n "${ansible_ssh_private_key_file}" ]]; then
  host_line="${host_line} ansible_ssh_private_key_file=\"${ansible_ssh_private_key_file}\""
fi

if [[ -n "${ansible_password}" ]]; then
  host_line="${host_line} ansible_password=\"${ansible_password}\""
fi

# Append extra_hostvars as key=value pairs when non-empty and not bare {}
if [[ -n "${extra_hostvars}" ]] && [[ "${extra_hostvars}" != "{}" ]]; then
  extra_kv="$(echo "${extra_hostvars}" | jq -r 'to_entries[] | "\(.key)=\"\(.value)\""' | tr '\n' ' ')"
  host_line="${host_line} ${extra_kv}"
fi

cat > "$tmp_dir/inventory.ini" <<INVENTORY
[all]
${host_line}
INVENTORY

# ── Build extra-vars.json ────────────────────────────────────────────────────
jq -n \
  --arg hostname             "${host_name}" \
  --arg workload_kind        "${workload_kind}" \
  --arg workload_lifecycle   "${workload_lifecycle}" \
  --arg workload_payload_b64 "${workload_payload_b64}" \
  --arg payload_hash         "${payload_hash}" \
  --arg role_source_hash     "${role_source_hash}" \
  --arg executor_environment_hash "${executor_environment_hash}" \
  '{
    "hostname":                $hostname,
    "workload_kind":           $workload_kind,
    "workload_lifecycle":      $workload_lifecycle,
    "workload_payload_b64":    $workload_payload_b64,
    "payload_hash":            $payload_hash,
    "role_source_hash":        $role_source_hash,
    "executor_environment_hash": $executor_environment_hash
  }' > "$tmp_dir/extra-vars.json"

# ── Build result-vars for Ansible ────────────────────────────────────────────
jq -n \
  --arg workload_result_path "${workload_result_path:-}" \
  '{"workload_result_path": $workload_result_path}' > "$tmp_dir/result-vars.json"

# ── Callback configuration ──────────────────────────────────────────────────
# garuda_apply_log writes one plain-text line per task into apply_log_file.
# After ansible exits we embed the file content into result.json so callers
# can read it via output.apply_log. tmp_dir cleanup happens via EXIT trap.
apply_log_file="$tmp_dir/apply.log"
: > "$apply_log_file"
export GARUDA_APPLY_LOG_PATH="$apply_log_file"

callback_dir="$repo_root/plugins/callback"
if [[ -n "${ANSIBLE_CALLBACK_PLUGINS:-}" ]]; then
  export ANSIBLE_CALLBACK_PLUGINS="${ANSIBLE_CALLBACK_PLUGINS}:${callback_dir}"
else
  export ANSIBLE_CALLBACK_PLUGINS="${callback_dir}"
fi

if [[ -n "${ANSIBLE_CALLBACKS_ENABLED:-}" ]]; then
  export ANSIBLE_CALLBACKS_ENABLED="${ANSIBLE_CALLBACKS_ENABLED},garuda_apply_log"
else
  export ANSIBLE_CALLBACKS_ENABLED="garuda_apply_log"
fi

cd "$repo_root"

# ── Run ansible-playbook ────────────────────────────────────────────────────
# Capture rc explicitly so we can finalize the apply_log even on failure.
set +e
ansible-playbook -i "$tmp_dir/inventory.ini" "$wrapper_playbook" \
  --extra-vars "@$tmp_dir/extra-vars.json" \
  --extra-vars "@$tmp_dir/result-vars.json"
ansible_rc=$?
set -e

# ── Finalize result.json with apply_log ─────────────────────────────────────
# Even on failure we want the partial log in state so operators can see
# how far the run progressed before it broke.
if [[ -n "${workload_result_path:-}" ]] && [[ -f "$apply_log_file" ]]; then
  if [[ -f "$workload_result_path" ]]; then
    jq --arg log "$(cat "$apply_log_file")" \
      '. + {apply_log: $log}' \
      "$workload_result_path" > "${workload_result_path}.new"
    mv "${workload_result_path}.new" "$workload_result_path"
  else
    jq -n --arg log "$(cat "$apply_log_file")" \
      '{outputs: {}, apply_log: $log}' > "$workload_result_path"
  fi
fi

exit $ansible_rc
