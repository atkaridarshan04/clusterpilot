# Shared EKS Pod Identity role for every addon in this project - see
# ../../../docs/concepts/irsa-and-pod-identity.md. Unlike IRSA, the trust
# policy targets the pods.eks.amazonaws.com service principal directly,
# with no per-cluster OIDC provider/issuer involved at all.

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  # keyed by index - a same-apply policy ARN is unknown at plan time, and
  # for_each needs every key known upfront.
  for_each = { for idx, arn in var.policy_arns : idx => arn }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# The actual role <-> ServiceAccount link - EKS Pod Identity Agent (the
# eks-pod-identity-agent addon) reads this at pod-start time and injects
# credentials, no annotation on the ServiceAccount itself required.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
  tags            = var.tags
}
