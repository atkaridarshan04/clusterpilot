variable "zone_name" {
  description = "Existing public Route53 hosted zone name"
  type        = string
}

variable "domain_name" {
  description = "Fully-qualified domain name to issue a certificate for"
  type        = string
}

variable "tags" {
  description = "Tags applied to the certificate"
  type        = map(string)
  default     = {}
}
