locals {
  # Environment
  env_region = "ap-northeast-1"

  # CloudWatch
  log_retention_days = 7

  # EKS
  cluster_name          = "kubeproxy-test"
  cluster_version       = "1.30"
  node_eks_version      = "1.30"
  k8s_service_ipv4_cidr = "172.21.0.0/16"
  node_subnet_ids       = ["subnet-6f8ec034"]
  node_placement_az     = "ap-northeast-1c"
  # TODO: Be sure to add cluster creator to this list
  eks_cluster_admin_arns = {
    "BastionAdmin" = "arn:aws:iam::464542629384:role/aws-reserved/sso.amazonaws.com/ap-southeast-1/AWSReservedSSO_BastionAdminAccess_7d4d256db6c8f196"
    "EdwardZhu"    = "arn:aws:iam::464542629384:user/edward.zhu"
    "KyleLi"       = "arn:aws:iam::464542629384:user/Kyle"
    "KylianHe"     = "arn:aws:iam::464542629384:user/kylian.he"
  }

  # default_tags
  tags = {
    Environment = local.cluster_name
    ManagedBy   = "Terraform"
    Product     = "Quant"
  }
}
