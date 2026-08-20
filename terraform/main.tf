module "vpc" {
  source       = "./modules/vpc"
  name         = "${local.name}-vpc"
  cluster_name = local.name
  vpc_cidr     = local.vpc_cidr
  azs          = local.azs
  tags         = local.tags
}

module "eks" {
  source             = "./modules/eks"
  cluster_name       = local.name
  kubernetes_version = local.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  node_instance_types = local.node_instance_types
  node_min_size       = local.node_min_size
  node_max_size       = local.node_max_size
  node_desired_size   = local.node_desired_size

  endpoint_public_access_cidrs = local.endpoint_public_access_cidrs

  tags = local.tags
}

module "ingress_controller" {
  source       = "./modules/ingress-controller"
  cluster_name = local.name
  region       = local.region
  vpc_id       = module.vpc.vpc_id
  tags         = local.tags

  # controller pods need the node group up to actually schedule
  depends_on = [module.eks]
}

module "eks_addons" {
  source             = "./modules/eks-addons"
  cluster_name       = local.name
  log_retention_days = local.log_retention_days
  tags               = local.tags

  depends_on = [module.eks, module.ingress_controller]
}

module "cluster_autoscaler" {
  source       = "./modules/cluster-autoscaler"
  cluster_name = local.name
  region       = local.region
  tags         = local.tags

  depends_on = [module.eks]
}

module "bastion" {
  source                    = "./modules/bastion"
  cluster_name              = local.name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
  kubernetes_version        = local.kubernetes_version
  vpc_id                    = module.vpc.vpc_id
  subnet_id                 = module.vpc.public_subnets[0]
  ssh_public_key            = var.ssh_public_key
  ssh_ingress_cidr          = local.bastion_ssh_cidr
  tags                      = local.tags

  depends_on = [module.eks]
}

# Least-privilege role for ../agent/ - uncomment (and the matching output
# in outputs.tf) to run the agent under its own scoped-down identity
# instead of your own AWS profile. See ../agent/README.md step 2.
# module "agent_role" {
#   source       = "./modules/agent-role"
#   cluster_name = local.name
#   tags         = local.tags
# }

module "argocd" {
  source                     = "./modules/argocd"
  repo_url                   = local.argocd_repo_url
  repo_path                  = local.argocd_repo_path
  repo_token                 = var.argocd_repo_token
  admin_password_bcrypt_hash = local.argocd_admin_password_bcrypt_hash

  # ArgoCD's own Helm chart creates several Services (argocd-server,
  # argocd-repo-server, argocd-redis, ...) - same admission-webhook race as
  # module.eks_addons, needs the ALB controller actually serving, not just
  # started. See docs/concepts/alb-networking-and-network-policy.md.
  depends_on = [module.eks, module.ingress_controller]
}

module "dns" {
  source      = "./modules/dns"
  zone_name   = local.dns_zone_name
  domain_name = local.domain_name
  tags        = local.tags
}

resource "local_file" "ingress_manifest" {
  content = templatefile("${path.module}/../k8s/ingress.yaml.tpl", {
    certificate_arn = module.dns.certificate_arn
  })
  filename = "${path.module}/../k8s/ingress.yaml"
}

resource "kubectl_manifest" "ingress" {
  yaml_body = local_file.ingress_manifest.content

  # Ingress creation goes through the ALB controller's admission webhook,
  # same race as module.eks_addons - needs that controller actually
  # serving, not just started - see docs/concepts/alb-networking-and-network-policy.md.
  depends_on = [module.ingress_controller]
}
