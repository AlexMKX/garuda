resource "kubernetes_namespace_v1" "garuda" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "garuda"
    }
  }

  # The Helm chart previously shipped a templates/namespace.yaml that
  # duplicated this; it was removed because the chart cannot reliably
  # create the namespace BEFORE helm_release writes its release Secret
  # to the same namespace (helm 2.17 provider against fresh k3s 1.31
  # observed `namespaces "<ns>" not found` even with
  # create_namespace=true). The explicit kubernetes_namespace_v1
  # creates the namespace through the Kubernetes API up-front; the
  # helm_release blocks below then have somewhere to store their
  # release records.
  lifecycle {
    ignore_changes = [metadata[0].labels]
  }
}

# garuda-cni installs Multus and Whereabouts DaemonSets. Helm `--wait`
# blocks until both DaemonSets are Ready, which means the
# NetworkAttachmentDefinition CRD has been registered with the API
# server by the Multus init container by the time control returns.
# The main garuda chart (NADs + ConfigMap) then applies cleanly. This
# split exists because shipping NADs and the CRD-installing DS in the
# same release races: Helm submits all manifests in one pass and the
# API server rejects the NADs because their CRD does not exist yet.
resource "helm_release" "garuda_cni" {
  name             = "garuda-cni"
  namespace        = kubernetes_namespace_v1.garuda.metadata[0].name
  create_namespace = false
  chart            = "${path.module}/charts/garuda-cni"
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      namespace  = var.namespace
      installCni = var.install_cni
    })
  ]
}

resource "helm_release" "garuda" {
  name             = "garuda"
  namespace        = kubernetes_namespace_v1.garuda.metadata[0].name
  create_namespace = false
  chart            = "${path.module}/charts/garuda"

  values = [
    yamlencode({
      namespace        = var.namespace
      backboneSubnet   = var.backbone_subnet
      borderSubnet     = var.border_subnet
      borderGateway    = cidrhost(var.border_subnet, 1)
      borderRangeStart = cidrhost(var.border_subnet, 2)
    })
  ]

  # Hard ordering: the NetworkAttachmentDefinition CRD is registered
  # by Multus inside garuda_cni; submitting the NADs before that release
  # is Ready produces `no matches for kind "NetworkAttachmentDefinition"`.
  depends_on = [helm_release.garuda_cni]
}
