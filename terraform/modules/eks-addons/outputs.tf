output "ebs_csi_role_arn" {
  value = module.ebs_csi_pod_identity.role_arn
}

output "cloudwatch_observability_role_arn" {
  value = module.cloudwatch_observability_pod_identity.role_arn
}
