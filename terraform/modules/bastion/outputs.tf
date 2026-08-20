output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "SSH target - `ssh -i <private-key> ec2-user@<this>`"
  value       = aws_instance.this.public_ip
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
