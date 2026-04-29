locals {
  payload_json = jsonencode(var.payload)
  payload_b64  = base64encode(local.payload_json)
  payload_hash = sha256(local.payload_json)

  role_dir = abspath("${path.module}/../../roles/${var.workload_kind}")

  role_source_files = sort(distinct(flatten([
    for pattern in [
      "tasks/**",
      "handlers/**",
      "templates/**",
      "files/**",
      "vars/**",
      "defaults/**",
      "meta/**",
      "action_plugins/**",
      "become_plugins/**",
      "cache_plugins/**",
      "callback_plugins/**",
      "cliconf_plugins/**",
      "connection_plugins/**",
      "doc_fragments/**",
      "library/**",
      "httpapi_plugins/**",
      "inventory_plugins/**",
      "netconf_plugins/**",
      "module_utils/**",
      "filter_plugins/**",
      "lookup_plugins/**",
      "plugins/**",
      "strategy_plugins/**",
      "terminal_plugins/**",
      "test_plugins/**",
      "vars_plugins/**",
      "requirements.yml",
      "requirements.yaml",
      ] : [
      for relpath in fileset(local.role_dir, pattern) : relpath
    ]
  ])))

  role_source_hash = sha256(join("\n", [
    for relpath in local.role_source_files : "${relpath}:${filesha256("${local.role_dir}/${relpath}")}"
  ]))

  executor_environment_entries = sort(concat(
    [
      "modules/linux_apply/files/apply_ansible_workload.yml:${filesha256(abspath("${path.module}/files/apply_ansible_workload.yml"))}",
      "galaxy.yml:${filesha256(abspath("${path.module}/../../galaxy.yml"))}",
      "meta/runtime.yml:${filesha256(abspath("${path.module}/../../meta/runtime.yml"))}",
    ],
    [
      for relpath in fileset(abspath("${path.module}/../../plugins"), "**") :
      "plugins/${relpath}:${filesha256(abspath("${path.module}/../../plugins/${relpath}"))}"
      if !can(regex("(^|/)__pycache__(/|$)|\\.pyc$", relpath))
    ],
    fileexists(abspath("${path.module}/../../ansible.cfg")) ? [
      "root/ansible.cfg:${filesha256(abspath("${path.module}/../../ansible.cfg"))}",
    ] : []
  ))

  executor_environment_hash = sha256(join("\n", local.executor_environment_entries))

  # SSH key resolution — two mutually-exclusive inputs flatten to two
  # effective values: the (expanded) path used in the inventory line, and the
  # raw key content forwarded to the helper via environment.
  ssh_key_raw         = try(var.connection_data.ssh_private_key, null)
  ssh_key_path        = try(var.connection_data.ssh_private_key_file, null)
  ssh_key_file_effect = local.ssh_key_path != null ? pathexpand(local.ssh_key_path) : ""
  ssh_key_fingerprint = local.ssh_key_raw != null ? sha256(local.ssh_key_raw) : ""

  inventory_vars = {
    host_name                    = var.host_name
    inventory_host               = var.connection_data.host
    ansible_user                 = var.connection_data.user
    ansible_connection           = var.connection_data.connection
    ansible_network_os           = var.connection_data.network_os
    ansible_ssh_private_key_file = local.ssh_key_file_effect
    ansible_password             = try(var.connection_data.password, null)
    extra_hostvars               = var.extra_hostvars
    workload_kind                = var.workload_kind
  }

  workload_sources_hash = sha256("${local.role_source_hash}:${local.executor_environment_hash}")

  wrapper_playbook = abspath("${path.module}/files/apply_ansible_workload.yml")
  helper_script    = abspath("${path.module}/files/run_linux_apply.sh")
  repo_root        = abspath("${path.module}/../..")

  result_path = abspath("${path.root}/.terraform/linux-apply/${var.host_name}-${var.workload_kind}.result.json")
}

resource "terraform_data" "runtime" {
  triggers_replace = {
    inventory_vars        = jsonencode(local.inventory_vars)
    workload_sources_hash = local.workload_sources_hash
    payload_hash          = local.payload_hash
    ssh_key_fingerprint   = local.ssh_key_fingerprint
    instance_token        = var.connection_data.instance_token
  }

  input = {
    host_name                    = var.host_name
    inventory_host               = var.connection_data.host
    ansible_user                 = var.connection_data.user
    ansible_connection           = var.connection_data.connection
    ansible_network_os           = var.connection_data.network_os
    ansible_ssh_private_key_file    = local.ssh_key_file_effect
    ansible_ssh_private_key_content = local.ssh_key_raw
    ansible_password                = try(var.connection_data.password, null)
    extra_hostvars                  = jsonencode(var.extra_hostvars)
    workload_kind                = var.workload_kind
    workload_payload_b64         = local.payload_b64
    destroy_payload_b64          = var.destroy_payload_override == null ? local.payload_b64 : base64encode(jsonencode(var.destroy_payload_override))
    payload_hash                 = local.payload_hash
    role_source_hash             = local.role_source_hash
    executor_environment_hash    = local.executor_environment_hash
    wrapper_playbook             = local.wrapper_playbook
    helper_script                = local.helper_script
    repo_root                    = local.repo_root
    result_path                  = local.result_path
  }

  provisioner "local-exec" {
    # run_linux_apply.sh - create-time provisioning
    command = self.input.helper_script
    environment = {
      host_name                        = self.input.host_name
      inventory_host                   = self.input.inventory_host
      ansible_user                     = self.input.ansible_user
      ansible_connection               = self.input.ansible_connection
      ansible_network_os               = self.input.ansible_network_os
      ansible_ssh_private_key_file     = self.input.ansible_ssh_private_key_file
      ansible_ssh_private_key_content  = self.input.ansible_ssh_private_key_content != null ? self.input.ansible_ssh_private_key_content : ""
      ansible_password                 = self.input.ansible_password != null ? self.input.ansible_password : ""
      extra_hostvars               = self.input.extra_hostvars
      workload_kind                = self.input.workload_kind
      workload_lifecycle           = "provision"
      workload_payload_b64         = self.input.workload_payload_b64
      payload_hash                 = self.input.payload_hash
      role_source_hash             = self.input.role_source_hash
      executor_environment_hash    = self.input.executor_environment_hash
      wrapper_playbook             = self.input.wrapper_playbook
      repo_root                    = self.input.repo_root
      workload_result_path         = self.input.result_path
    }
  }

  provisioner "local-exec" {
    # run_linux_apply.sh - destroy-time teardown
    when    = destroy
    command = "test -f \"${self.input.helper_script}\" && \"${self.input.helper_script}\" || echo \"WARN: helper_script not found at ${self.input.helper_script}, skipping destroy teardown\""
    environment = {
      host_name                        = self.input.host_name
      inventory_host                   = self.input.inventory_host
      ansible_user                     = self.input.ansible_user
      ansible_connection               = self.input.ansible_connection
      ansible_network_os               = try(self.input.ansible_network_os, "linux")
      ansible_ssh_private_key_file     = self.input.ansible_ssh_private_key_file
      ansible_ssh_private_key_content  = self.input.ansible_ssh_private_key_content != null ? self.input.ansible_ssh_private_key_content : ""
      ansible_password                 = self.input.ansible_password != null ? self.input.ansible_password : ""
      extra_hostvars               = self.input.extra_hostvars
      workload_kind                = self.input.workload_kind
      workload_lifecycle           = "destroy"
      workload_payload_b64         = try(self.input.destroy_payload_b64, self.input.workload_payload_b64)
      payload_hash                 = self.input.payload_hash
      role_source_hash             = self.input.role_source_hash
      executor_environment_hash    = self.input.executor_environment_hash
      wrapper_playbook             = self.input.wrapper_playbook
      repo_root                    = self.input.repo_root
      workload_result_path         = try(self.input.result_path, "")
    }
  }
}

locals {
  raw_result      = fileexists(local.result_path) ? jsondecode(file(local.result_path)) : tomap({})
  ansible_outputs = try(local.raw_result.outputs, tomap({}))
  merged_outputs  = merge(var.payload, local.ansible_outputs)
}
