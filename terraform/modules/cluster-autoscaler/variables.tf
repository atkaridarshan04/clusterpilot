variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region, passed to the autoscaler chart"
  type        = string
}

variable "chart_version" {
  description = "cluster-autoscaler helm chart version"
  type        = string
  default     = "9.59.0"
}

variable "tags" {
  description = "Tags applied to the IAM resources"
  type        = map(string)
  default     = {}
}
