# Auto-discovers the ASG via tags EKS already applies to managed node
# groups - no extra tagging needed.

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "ClusterAutoscalerPolicy-${var.cluster_name}"
  description = "IAM policy for the Kubernetes Cluster Autoscaler"
  policy      = file("${path.module}/iam_policy.json")
  tags        = var.tags
}

# EKS Pod Identity, same reasoning as modules/ingress-controller - see
# docs/concepts/irsa-and-pod-identity.md.
module "pod_identity" {
  source = "../pod-identity-role"

  role_name       = "${var.cluster_name}-cluster-autoscaler"
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  policy_arns     = [aws_iam_policy.cluster_autoscaler.arn]
  tags            = var.tags
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = "kube-system"

  set = [
    { name = "autoDiscovery.clusterName", value = var.cluster_name },
    { name = "awsRegion", value = var.region },
    { name = "rbac.serviceAccount.create", value = "true" },
    { name = "rbac.serviceAccount.name", value = "cluster-autoscaler" },
    # defaults are 10m/10m - shortened for faster feedback in this demo.
    { name = "extraArgs.scale-down-unneeded-time", value = "3m" },
    { name = "extraArgs.scale-down-delay-after-add", value = "3m" },
  ]

  depends_on = [module.pod_identity]
}
