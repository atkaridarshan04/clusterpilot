variable "repo_url" {
  description = "HTTPS git URL ArgoCD pulls manifests from (not an SSH host alias - the repo-server runs inside the cluster and can't see your local ~/.ssh/config)"
  type        = string
}

variable "repo_path" {
  description = "Path within the repo containing the manifests to sync"
  type        = string
}

variable "repo_revision" {
  description = "Git branch/tag ArgoCD tracks"
  type        = string
  default     = "main"
}

variable "repo_token" {
  description = "GitHub PAT for cloning repo_url, stored as a k8s Secret, never in a manifest. Leave empty (the default) for a public repo_url - no Secret gets created at all, and ArgoCD clones it anonymously"
  type        = string
  sensitive   = true
  default     = ""
}

variable "admin_password_bcrypt_hash" {
  description = "bcrypt hash of the ArgoCD admin password (generate with: htpasswd -nbBC 10 \"\" <password>, then drop the leading colon)"
  type        = string
  sensitive   = true
}
