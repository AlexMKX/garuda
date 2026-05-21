mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace       = "garuda"
  backbone_subnet = "10.42.0.0/24"
  border_subnet   = "10.43.0.0/24"
}

run "garuda_chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.garuda.chart, "/charts/garuda")
    error_message = "helm_release.garuda.chart must point at ${path.module}/charts/garuda"
  }
}

run "garuda_cni_chart_path_resolves_to_bundled_chart" {
  command = plan

  assert {
    condition     = endswith(helm_release.garuda_cni.chart, "/charts/garuda-cni")
    error_message = "helm_release.garuda_cni.chart must point at ${path.module}/charts/garuda-cni"
  }
}

run "garuda_cni_waits_for_ready" {
  command = plan

  # The split exists because the NAD CRD is registered at runtime by the
  # Multus DS. wait=true is what guarantees the CRD is observable by the
  # time the dependent helm_release.garuda runs. Regression-locked here.
  assert {
    condition     = helm_release.garuda_cni.wait == true
    error_message = "helm_release.garuda_cni.wait must be true so the Multus CRD exists before the main chart applies NADs."
  }
}

run "namespace_propagates_to_both_releases" {
  command = plan

  variables {
    namespace = "garuda-pt"
  }

  assert {
    condition     = helm_release.garuda.namespace == "garuda-pt"
    error_message = "helm_release.garuda.namespace must echo var.namespace"
  }

  assert {
    condition     = helm_release.garuda_cni.namespace == "garuda-pt"
    error_message = "helm_release.garuda_cni.namespace must echo var.namespace"
  }
}

run "garuda_values_include_subnets" {
  command = plan

  variables {
    namespace       = "garuda-pt"
    backbone_subnet = "10.142.0.0/24"
    border_subnet   = "10.143.0.0/24"
    install_cni     = false
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"namespace\": \"garuda-pt\"")
    error_message = "rendered garuda values must contain namespace from var.namespace"
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"backboneSubnet\": \"10.142.0.0/24\"")
    error_message = "rendered garuda values must contain backboneSubnet from var.backbone_subnet"
  }

  assert {
    condition     = strcontains(helm_release.garuda.values[0], "\"borderSubnet\": \"10.143.0.0/24\"")
    error_message = "rendered garuda values must contain borderSubnet from var.border_subnet"
  }

  # The garuda chart no longer ships CNI manifests; installCni belongs to
  # garuda_cni only.
  assert {
    condition     = !strcontains(helm_release.garuda.values[0], "installCni")
    error_message = "garuda chart values must not contain installCni; it belongs to the garuda-cni chart."
  }
}

run "garuda_cni_values_carry_install_cni_flag" {
  command = plan

  variables {
    namespace   = "garuda-pt"
    install_cni = false
  }

  assert {
    condition     = strcontains(helm_release.garuda_cni.values[0], "\"namespace\": \"garuda-pt\"")
    error_message = "rendered garuda-cni values must contain namespace from var.namespace"
  }

  assert {
    condition     = strcontains(helm_release.garuda_cni.values[0], "\"installCni\": false")
    error_message = "rendered garuda-cni values must contain installCni from var.install_cni"
  }
}

run "outputs_with_default_namespace" {
  command = plan

  assert {
    condition     = output.namespace == "garuda"
    error_message = "output.namespace must echo var.namespace"
  }

  assert {
    condition     = output.backbone_nad_name == "backbone"
    error_message = "output.backbone_nad_name must be the static value 'backbone'"
  }

  assert {
    condition     = output.border_nad_name == "border"
    error_message = "output.border_nad_name must be the static value 'border'"
  }
}

run "output_namespace_echoes_custom_value" {
  command = plan

  variables {
    namespace = "garuda-pt"
  }

  assert {
    condition     = output.namespace == "garuda-pt"
    error_message = "output.namespace must echo a non-default var.namespace; this is the contract wireguard/kube consumes."
  }
}

run "invalid_namespace_rejected" {
  command = plan

  variables {
    namespace = "Garuda_Bad"
  }

  expect_failures = [var.namespace]
}

run "invalid_backbone_subnet_rejected" {
  command = plan

  variables {
    backbone_subnet = "not-a-cidr"
  }

  expect_failures = [var.backbone_subnet]
}
