# Policy JSON is the upstream file from
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
  description = "IAM policy for the AWS Load Balancer Controller"
  policy      = file("${path.module}/iam_policy.json")
  tags        = var.tags
}

# EKS Pod Identity rather than IRSA - see docs/concepts/irsa-and-pod-identity.md.
module "pod_identity" {
  source = "../pod-identity-role"

  role_name       = "${var.cluster_name}-alb-controller"
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  policy_arns     = [aws_iam_policy.alb_controller.arn]
  tags            = var.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = "kube-system"

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  # Pod Identity Agent injects credentials for this namespace/service
  # account pairing at pod-start time - no role-arn annotation on the
  # ServiceAccount needed, unlike IRSA.
  depends_on = [module.pod_identity]
}
