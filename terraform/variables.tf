# Required inputs, no defaults - pass via TF_VAR_<name>/a gitignored
# *.tfvars locally, or as repo secrets in CI. See terraform/README.md's
# "One-time repo setup".

variable "ssh_public_key" {
  description = "Public key (e.g. contents of ~/.ssh/id_ed25519.pub) registered for SSH access to the bastion - never commit the matching private key, and don't pass it via a default here"
  type        = string
}

variable "argocd_repo_token" {
  description = "GitHub PAT for ArgoCD's repo-server to clone this repo - leave unset for a public fork, ArgoCD then clones anonymously and no k8s Secret gets created at all. Only needed if your fork is private."
  type        = string
  sensitive   = true
  default     = ""
}
