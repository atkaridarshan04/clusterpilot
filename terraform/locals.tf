data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}


locals {
  region = "ap-south-1"
  name   = "clusterpilot"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  kubernetes_version = "1.35"

  node_instance_types = ["t3a.medium"]
  node_min_size       = 3
  node_max_size       = 7
  node_desired_size   = 4

  log_retention_days = 30

  # Wide open for now - narrow to a specific trusted range when that's known.
  endpoint_public_access_cidrs = ["0.0.0.0/0"]
  bastion_ssh_cidr             = "0.0.0.0/0"

  argocd_repo_url  = "https://github.com/atkaridarshan04/clusterpilot.git"
  argocd_repo_path = "k8s"
  # bcrypt hash of "admin123" - htpasswd -nbBC 10 "" admin123, leading colon dropped
  argocd_admin_password_bcrypt_hash = "$2y$10$FZUwwK/ouAWUsPsX9KaCresWC9dpDMYWRIanSOMx.2WJKt7Nw//zO"

  dns_zone_name = "atkaridarshan.online"
  domain_name   = "wordpress.atkaridarshan.online"

  tags = {
    Name      = "clusterpilot"
    Project   = "clusterpilot"
    Email     = "atkaridarshan04@gmail.com"
    ManagedBy = "Terraform"
  }
}
