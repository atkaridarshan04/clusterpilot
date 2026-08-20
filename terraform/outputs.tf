output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "intra_subnets" {
  value = module.vpc.intra_subnets
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "certificate_arn" {
  value = module.dns.certificate_arn
}

output "bastion_public_ip" {
  description = "SSH target - `ssh -i <private-key> ec2-user@<this>`"
  value       = module.bastion.public_ip
}

# Uncomment along with module.agent_role in main.tf.
# output "agent_role_arn" {
#   value = module.agent_role.role_arn
# }
