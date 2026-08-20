output "state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_OIDC_ROLE_ARN repo variable (Settings -> Secrets and variables -> Actions -> Variables)"
  value       = module.github_oidc.role_arn
}
