variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the amazon-cloudwatch-observability addon's auto-created Container Insights log groups"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to the IAM resources"
  type        = map(string)
  default     = {}
}
