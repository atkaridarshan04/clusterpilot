# Required inputs, no defaults - pass via TF_VAR_<name>/a gitignored
# *.tfvars locally, or as repo secrets in CI. See terraform/README.md's
# "One-time repo setup".

variable "ssh_public_key" {
  description = "Public key (e.g. contents of ~/.ssh/id_ed25519.pub) registered for SSH access to the bastion - never commit the matching private key, and don't pass it via a default here"
  type        = string
}

variable "argocd_repo_token" {
  description = "GitHub PAT for ArgoCD's repo-server to clone this repo - only actually needed if your fork is private (a public fork clones anonymously). Still a required input either way; pass any placeholder string if public."
  type        = string
  sensitive   = true
}
