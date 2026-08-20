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
