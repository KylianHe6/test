resource "helm_release" "cilium" {
  depends_on = [
    null_resource.eks_cluster_ready
  ]

  name      = "cilium"
  namespace = "kube-system"

  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.16.1"

  values = [chomp(replace(file("cilium-values.yaml"), "\r\n", "\n"))]
  set {
    name  = "ipv4NativeRoutingCIDR"
    value = data.aws_vpc.vpc-Quant-Tokyo.cidr_block
  }
  set {
    name  = "k8sServiceHost"
    value = replace(module.eks.cluster_endpoint, "https://", "")
  }

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  wait            = true
}
