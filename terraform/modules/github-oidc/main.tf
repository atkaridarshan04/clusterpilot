# Lets GitHub Actions assume an AWS role via short-lived, per-run OIDC
# tokens - no long-lived AWS keys stored as repo secrets. See
# ../../../docs/concepts/github-actions-oidc.md for the mechanics.

data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# This provider is account-wide, not per-repo - AWS allows only one IAM
# OIDC provider per (account, issuer URL), and every GitHub repo shares the
# same issuer (token.actions.githubusercontent.com). If any other project
# in this AWS account has ever set up GitHub Actions OIDC before, one
# already exists - set create_oidc_provider = false and pass its ARN via
# existing_oidc_provider_arn instead of creating a duplicate (which fails
# with EntityAlreadyExists). See ../../../docs/concepts/github-actions-oidc.md.
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]
  tags            = var.tags
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/${var.github_repo}:*",
        "repo:${var.github_owner}@*/${var.github_repo}@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = var.tags
}

resource "aws_iam_policy" "ci" {
  name        = "${var.name}-github-actions-terraform"
  description = "Permissions this repo's Terraform config needs to plan/apply/destroy the EKS platform"
  policy = templatefile("${path.module}/ci-terraform-policy.json.tpl", {
    name             = var.name
    state_bucket_arn = var.state_bucket_arn
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci.arn
}
