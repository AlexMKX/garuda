provider "routeros" {
  hosturl  = "api://${var.routeros.management_host}"
  username = var.routeros.user
  password = var.routeros_password
  insecure = true
}

# --- Edge k3s providers (one instance per edge slug). ---
# `for_each = var.edges` creates a provider instance per edge:
# helm.edge["pt"], kubernetes.edge["de"], etc. Consumer modules pass
# `helm.edge[each.key]` / `kubernetes.edge[each.key]` from inside a
# matching `for_each = var.edges` module block, so adding a third
# edge means a single inputs.tfvars.yaml entry — providers and
# consumers fan out together.
#
# Requires OpenTofu >= 1.10 for `for_each` in provider blocks. The
# required_version floor in versions.tf enforces this.
#
# The kubeconfig that k3s ships at /etc/rancher/k3s/k3s.yaml is
# fetched by garuda-tunnel via SFTP and exposed in
# local.edges_kubeconfig. The local SSH-forward port lives in
# local.edges_endpoint. The apiserver cert SANs already include
# 127.0.0.1, so TLS validates against the forwarded address; no
# --tls-san change or tls_server_name override is required.

provider "helm" {
  alias    = "edge"
  for_each = var.edges

  kubernetes {
    host                   = local.edges_endpoint[each.key]
    cluster_ca_certificate = base64decode(local.edges_kubeconfig[each.key].clusters[0].cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.edges_kubeconfig[each.key].users[0].user["client-certificate-data"])
    client_key             = base64decode(local.edges_kubeconfig[each.key].users[0].user["client-key-data"])
  }
}

provider "kubernetes" {
  alias    = "edge"
  for_each = var.edges

  host                   = local.edges_endpoint[each.key]
  cluster_ca_certificate = base64decode(local.edges_kubeconfig[each.key].clusters[0].cluster["certificate-authority-data"])
  client_certificate     = base64decode(local.edges_kubeconfig[each.key].users[0].user["client-certificate-data"])
  client_key             = base64decode(local.edges_kubeconfig[each.key].users[0].user["client-key-data"])
}
