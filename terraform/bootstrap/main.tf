terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_144:cross-region replication is overkill for a single-account, single-region learning project
  #checkov:skip=CKV2_AWS_62:no event consumer (SNS/SQS/Lambda) wired up - notifications with nothing subscribed add nothing
  #checkov:skip=CKV2_AWS_61:state files are tiny and versioning already exists for recovery - a lifecycle policy would only add noise here
  #checkov:skip=CKV_AWS_18:access logging needs a separate log-destination bucket - not worth the extra bucket/IAM for a personal state bucket
  #checkov:skip=CKV_AWS_145:same tradeoff as the CloudWatch logs - AES256 (already enabled below) is enough, not worth KMS key management here
  # Account id suffix keeps the bucket name globally unique
  bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# One-time, run-with-your-own-credentials setup, same as the state bucket
# above - creates the GitHub OIDC provider + IAM role the CI workflows
# assume afterward. See ../../docs/concepts/github-actions-oidc.md.
module "github_oidc" {
  source           = "../modules/github-oidc"
  name             = var.name
  github_owner     = var.github_owner
  github_repo      = var.github_repo
  state_bucket_arn = aws_s3_bucket.tfstate.arn
  tags             = var.tags
}
