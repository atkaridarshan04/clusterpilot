# Lets GitHub Actions assume an AWS role via short-lived, per-run OIDC
# tokens - no long-lived AWS keys stored as repo secrets. See
# ../../../docs/concepts/github-actions-oidc.md for the mechanics.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to this one repo - any ref/branch/PR/workflow_dispatch within
    # it, but no other repo under the same GitHub account can assume this
    # role. Narrow further to e.g. "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
    # if only the default branch should ever be able to apply/destroy.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:*"]
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
