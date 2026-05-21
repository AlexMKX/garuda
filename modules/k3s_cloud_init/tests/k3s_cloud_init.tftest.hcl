# Unit tests for the render. No providers required.

run "default_render_contains_installer_and_bind" {
  command = plan
  assert {
    condition     = strcontains(output.user_data_parts[0], "curl -sfL https://get.k3s.io")
    error_message = "Default install_url and curl pipe must be present."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--tls-san=127.0.0.1")
    error_message = "Invariant --tls-san=127.0.0.1 must be present."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--https-listen-port=6443")
    error_message = "Invariant --https-listen-port=6443 must be present."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "--bind-address=")
    error_message = "Stale --bind-address invariant must not appear; the apiserver listens on all interfaces and is constrained by the host firewall."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "--advertise-address=")
    error_message = "--advertise-address must not be set; kubernetes endpoint validation forbids the loopback range for the `kubernetes` service Endpoints, and we have no public IP to advertise."
  }
  assert {
    condition     = startswith(output.user_data_parts[0], "#cloud-config")
    error_message = "Rendered part must start with #cloud-config."
  }
}

run "version_pinned_emits_install_k3s_version_env" {
  command = plan
  variables {
    k3s_version = "v1.30.5+k3s1"
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "INSTALL_K3S_VERSION=v1.30.5+k3s1")
    error_message = "Pinned version must surface as INSTALL_K3S_VERSION env."
  }
}

run "version_null_omits_env" {
  command = plan
  assert {
    condition     = !strcontains(output.user_data_parts[0], "INSTALL_K3S_VERSION=")
    error_message = "Default (null) version must not emit INSTALL_K3S_VERSION env."
  }
}

run "install_url_override_used" {
  command = plan
  variables {
    install_url = "https://example.net/k3s-install"
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "https://example.net/k3s-install")
    error_message = "Override install_url must surface."
  }
  assert {
    condition     = !strcontains(output.user_data_parts[0], "get.k3s.io")
    error_message = "Default install_url must not leak when overridden."
  }
}

run "extra_flags_appended_after_invariants" {
  command = plan
  variables {
    extra_flags = ["--disable=traefik", "--node-label=role=edge"]
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--disable=traefik")
    error_message = "extra_flags[0] must surface."
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "--node-label=role=edge")
    error_message = "extra_flags[1] must surface."
  }
}

run "extra_install_env_passed_to_curl_pipe" {
  command = plan
  variables {
    extra_install_env = { INSTALL_K3S_CHANNEL = "latest" }
  }
  assert {
    condition     = strcontains(output.user_data_parts[0], "INSTALL_K3S_CHANNEL=latest")
    error_message = "extra_install_env entry must surface."
  }
}

run "reject_invalid_version_format" {
  command = plan
  variables {
    k3s_version = "1.30"
  }
  expect_failures = [var.k3s_version]
}

run "reject_non_https_install_url" {
  command = plan
  variables {
    install_url = "http://get.k3s.io"
  }
  expect_failures = [var.install_url]
}

run "reject_extra_flag_without_dashdash" {
  command = plan
  variables {
    extra_flags = ["disable=traefik"]
  }
  expect_failures = [var.extra_flags]
}

run "reject_extra_install_env_non_install_prefix" {
  command = plan
  variables {
    extra_install_env = { K3S_TOKEN = "abc" }
  }
  expect_failures = [var.extra_install_env]
}
