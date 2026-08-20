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

variable "create_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider. Set false if this AWS account already has one (it's account-wide, shared by every repo, not per-project) - AWS rejects a second one for the same issuer URL with EntityAlreadyExists"
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider to reuse, e.g. arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com - required when create_oidc_provider is false, ignored otherwise"
  type        = string
  default     = ""

  validation {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != ""
    error_message = "existing_oidc_provider_arn is required when create_oidc_provider is false."
  }
}

variable "tags" {
  description = "Tags applied to the IAM resources"
  type        = map(string)
  default     = {}
}
