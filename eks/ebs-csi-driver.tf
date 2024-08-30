####################################################
#  Install EBS CSI
####################################################
# install snapshotter
resource "null_resource" "external-snapshotter" {
  depends_on = [
    null_resource.eks_cluster_ready,
    helm_release.cilium
  ]

  triggers = {
    cluster_id = module.eks.cluster_oidc_issuer_url
  }

  provisioner "local-exec" {
    command = chomp(replace(<<-EOT
      ${templatefile("install-snapshotter.sh", {
      cluster_name = local.cluster_name
  })}
      EOT
, "\r\n", "\n"))
}
}

module "ebs_csi_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "AmazonEBSCSIDriver-${local.cluster_name}"
  role_description      = "The role for aws-ebs-csi service account in the EKS cluster"
  role_path             = "/"
  create_role           = true
  attach_ebs_csi_policy = true

  oidc_providers = {
    (local.cluster_name) = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

data "aws_eks_addon_version" "ebs_csi_addon" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi_addon" {
  depends_on = [
    helm_release.cilium,
    null_resource.external-snapshotter,
    module.ebs_csi_role
  ]

  cluster_name                = local.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi_addon.version
  service_account_role_arn    = module.ebs_csi_role.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "kubernetes_storage_class_v1" "gp3" {
  depends_on = [
    aws_eks_addon.ebs_csi_addon
  ]

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = true
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
  # reclaim_policy      = "Retain"
  # mount_options = ["file_mode=0700", "dir_mode=0777", "mfsymlinks", "uid=1000", "gid=1000", "nobrl", "cache=none"]
}
