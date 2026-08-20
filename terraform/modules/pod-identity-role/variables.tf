variable "role_name" {
  description = "IAM role name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name to associate this role with"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account this role is for"
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name this role is for"
  type        = string
}

variable "policy_arns" {
  description = "IAM policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the role and its pod identity association"
  type        = map(string)
  default     = {}
}
