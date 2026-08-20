output "role_arn" {
  description = "Pass this to actions/configure-aws-credentials' role-to-assume input"
  value       = aws_iam_role.ci.arn
}
