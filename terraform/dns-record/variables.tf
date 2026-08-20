variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "zone_name" {
  description = "Existing public Route53 hosted zone name"
  type        = string
  default     = "atkaridarshan04.online"
}

variable "domain_name" {
  description = "Fully-qualified domain name to point at the ALB"
  type        = string
  default     = "wordpress.atkaridarshan04.online"
}

variable "cluster_name" {
  description = "EKS cluster name - used to look up the ALB via its tags"
  type        = string
  default     = "clusterpilot"
}

variable "ingress_namespace" {
  description = "Namespace of the Ingress whose ALB this domain should point at"
  type        = string
  default     = "default"
}

variable "ingress_name" {
  description = "Name of the Ingress whose ALB this domain should point at"
  type        = string
  default     = "app"
}
