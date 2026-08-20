data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.arn]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-agent"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = var.tags
}

resource "aws_iam_policy" "eks_mcp_server" {
  name        = "EksMcpServerReadOnly-${var.cluster_name}"
  description = "Read-only policy for awslabs.eks-mcp-server, used by ../../agent/"
  policy      = file("${path.module}/eks-mcp-iam-policy.json")
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_mcp_server" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.eks_mcp_server.arn
}
