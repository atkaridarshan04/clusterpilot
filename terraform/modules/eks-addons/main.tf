# Grouped in one module: both addons are just an EKS Pod Identity role + an
# `aws_eks_addon`, nothing else.

module "ebs_csi_pod_identity" {
  source = "../pod-identity-role"

  role_name       = "${var.cluster_name}-ebs-csi"
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  policy_arns     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  tags            = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  tags         = var.tags

  # No service_account_role_arn - that's the IRSA-style wiring. With Pod
  # Identity, the addon's default ServiceAccount (ebs-csi-controller-sa)
  # just needs a matching association to exist, which it does above.
  depends_on = [module.ebs_csi_pod_identity]
}

# Both managed policies are required, not just the CloudWatch one - this
# addon also wires up CloudWatch Application Signals (X-Ray) alongside
# Container Insights.

module "cloudwatch_observability_pod_identity" {
  source = "../pod-identity-role"

  role_name       = "${var.cluster_name}-cloudwatch-observability"
  cluster_name    = var.cluster_name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
  ]
  tags = var.tags
}

locals {
  container_insights_log_types = ["application", "dataplane", "host", "performance"]
}

resource "aws_cloudwatch_log_group" "container_insights" {
  #checkov:skip=CKV_AWS_338:log_retention_days is set short on purpose to keep costs low on this learning cluster
  #checkov:skip=CKV_AWS_158:KMS encryption isn't worth the added key management overhead for short-lived container-insights logs here
  for_each = toset(local.container_insights_log_types)

  name              = "/aws/containerinsights/${var.cluster_name}/${each.value}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  tags         = var.tags

  # Fluent Bit auto-creates these log groups itself if they don't exist yet -
  # ordering after them guarantees Terraform's own resources (with the
  # retention/tags above) win that race instead of relying on API call speed.
  depends_on = [aws_cloudwatch_log_group.container_insights, module.cloudwatch_observability_pod_identity]
}
