module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
      # needed for the NetworkPolicies in k8s/policies.yaml to actually be enforced
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    # needed for the wordpress HPA in k8s/policies.yaml to read pod CPU metrics
    metrics-server = {}
  }

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Grants whoever runs `apply` cluster-admin via an EKS access entry
  enable_cluster_creator_admin_permissions = true

  # Every addon role in this project uses EKS Pod Identity, not IRSA - no
  # need for the module to also create an IAM OIDC provider for the
  # cluster. See ../../../docs/concepts/irsa-and-pod-identity.md.
  enable_irsa = false

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  eks_managed_node_groups = {
    example = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # replaces the whole default mapping, so volume_size/type repeat here
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 20
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }
    }
  }

  tags = var.tags
}
