################################################################################
# EKS Module
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # EKS default is "172.20.0.0/16" (B类内网地址 172.16.0.0-172.31.255.255 网络数：16)
  cluster_service_ipv4_cidr = local.k8s_service_ipv4_cidr

  vpc_id     = data.aws_vpc.vpc-Quant-Tokyo.id
  subnet_ids = data.aws_subnets.vpc-Quant-Tokyo_subnets.ids

  cluster_enabled_log_types   = []
  create_cloudwatch_log_group = false

  # Encryption key
  create_kms_key                  = true
  enable_kms_key_rotation         = true
  kms_key_deletion_window_in_days = 7
  kms_key_administrators          = tolist(values(local.eks_cluster_admin_arns))
  cluster_encryption_config       = { resources = ["secrets"] }

  access_entries = {
    for k, v in local.eks_cluster_admin_arns :
    k => {
      principal_arn = v
      policy_associations = {
        # https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html#access-policy-permissions
        AmazonEKSClusterAdminPolicy = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Extend the module created cluster security group rules
  cluster_security_group_additional_rules = {}

  # Extend the module created node security group rules
  node_security_group_additional_rules = {
    ingress_all = {
      type        = "ingress"
      description = "All from trusted"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = [
        data.aws_vpc.vpc-Quant-Tokyo.cidr_block,
      ]
    }
    ingress_NodePorts = {
      type        = "ingress"
      description = "NodePorts from Office"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      cidr_blocks = [
        "58.33.91.128/29",    # SH office 6F Telecom
        "58.246.122.30/32",   # SH office 6F Unicom
        "210.209.77.136/29",  # HK Office 1 new
        "218.255.251.130/32", # HK Office 2
        "165.21.105.184/30",  # SGP Office
      ]
    }
  }

  # EKS Managed Node Group(s) Default Configuration
  eks_managed_node_group_defaults = {
    use_custom_launch_template = true

    cluster_version            = local.node_eks_version
    platform                   = "AL2023"
    ami_type                   = "AL2023_x86_64_STANDARD"
    capacity_type              = "ON_DEMAND"
    enable_monitoring          = false
    iam_role_attach_cni_policy = true
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    metadata_options = {}

    ebs_optimized = true

    block_device_mappings = [
      {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 20
          volume_type           = "gp3"
          delete_on_termination = true
        }
      }
    ]

    vpc_id                                = data.aws_vpc.vpc-Quant-Tokyo.id
    attach_cluster_primary_security_group = false
    # vpc_security_group_ids                = [aws_security_group.additional.id]

    update_config = {
      # max_unavailable_percentage = 50 # or set `max_unavailable`
      max_unavailable = 1
    }

    taints = {
      cilium = {
        key    = "node.cilium.io/agent-not-ready"
        value  = "true"
        effect = "NO_EXECUTE"
      }
    }
  }

  # EKS Managed Node Group
  eks_managed_node_groups = {
    ManagedNode = {
      name        = local.cluster_name
      description = "EKS managed node launch template"

      subnet_ids = local.node_subnet_ids

      create_placement_group = true
      placement_group_az     = local.node_placement_az

      min_size       = 1
      max_size       = 10
      desired_size   = 2
      instance_types = ["c6in.xlarge"]
      labels = {
        nodeGroup = "PublicNodeGroup"
      }
    }
  }

  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
#       configuration_values = jsonencode({
#         env = {
#           # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
#           ENABLE_PREFIX_DELEGATION = "true"
#           WARM_PREFIX_TARGET       = "1"
#           WARM_ENI_TARGET          = "0"
#         }
#       })
    }
  }

}

resource "time_sleep" "wait_1_minute" {
  depends_on = [
    module.eks
  ]

  create_duration = "1m"
}

resource "null_resource" "eks_cluster_ready" {
  depends_on = [
    time_sleep.wait_1_minute
  ]

  triggers = {
    cluster_id = module.eks.cluster_oidc_issuer_url
  }

  provisioner "local-exec" {
    command = chomp(replace(<<-EOT
      ${templatefile("eks-post-install.sh", {
      aws_profile  = "prop"
      aws_region   = local.env_region
      cluster_name = local.cluster_name
  })}
    EOT
, "\r\n", "\n"))
}
}

# resource "null_resource" "cilium_tuning" {
#   depends_on = [
#     time_sleep.wait_1_minute
#   ]
#
#   provisioner "local-exec" {
#     interpreter = ["bash", "-c"]
#     command  = chomp(replace(<<-EOT
#       ${templatefile("cilium-tuning-init.sh", {
#       aws_profile  = "prop"
#       aws_region   = local.env_region
#   })}
#     EOT
# , "\r\n", "\n"))
#   }
# }

output "eks-oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

####################################################
#  Install coredns addon after cilium
####################################################
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "coredns_addon" {
  depends_on = [
    helm_release.cilium
  ]

  cluster_name                = local.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
