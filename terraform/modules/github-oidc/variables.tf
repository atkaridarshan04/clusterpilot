variable "name" {
  description = "Name prefix for the IAM role/policy created here"
  type        = string
}

variable "github_owner" {
  description = "GitHub username/org that owns the repo allowed to assume this role"
  type        = string
}

variable "github_repo" {
  description = "Repo name (without owner) allowed to assume this role"
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state bucket the CI role needs read/write access to"
  type        = string
}

variable "tags" {
  description = "Tags applied to the IAM resources"
  type        = map(string)
  default     = {}
}
