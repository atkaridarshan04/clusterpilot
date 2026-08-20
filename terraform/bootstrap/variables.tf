variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-south-1"
}

variable "name" {
  description = "Name prefix for the state bucket and the GitHub Actions IAM role"
  type        = string
  default     = "clusterpilot"
}

variable "github_owner" {
  description = "GitHub username/org that owns this repo, e.g. \"atkaridarshan04\" - the only account allowed to assume the CI role"
  type        = string
  default     = "atkaridarshan04"
}

variable "github_repo" {
  description = "Repo name (without owner), e.g. \"clusterpilot\""
  type        = string
  default     = "clusterpilot"
}

variable "create_github_oidc_provider" {
  description = "Set false if this AWS account already has a GitHub Actions OIDC provider from another project - it's account-wide (one per account per issuer URL), not per-repo, so AWS rejects a second one. Pass its ARN via existing_github_oidc_provider_arn instead"
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider, e.g. arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com - required when create_github_oidc_provider is false"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to bootstrap resources"
  type        = map(string)
  default = {
    Name      = "clusterpilot"
    Project   = "clusterpilot"
    Email     = "atkaridarshan04@gmail.com"
    ManagedBy = "Terraform"
  }
}
