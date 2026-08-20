variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster (for the bastion's eks:DescribeCluster policy)"
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS cluster's own security group - the bastion gets an explicit ingress rule added to it"
  type        = string
}

variable "kubernetes_version" {
  description = "Cluster's Kubernetes version, e.g. \"1.35\" - kubectl is pinned to match"
  type        = string
}

variable "vpc_id" {
  description = "VPC the bastion's security group is created in"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet the bastion instance is launched into (needs a public IP for direct SSH)"
  type        = string
}

variable "instance_type" {
  description = "Bastion EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "Public key (e.g. contents of ~/.ssh/id_ed25519.pub) registered for SSH access - the matching private key never touches Terraform or its state"
  type        = string
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH into the bastion on port 22"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}
