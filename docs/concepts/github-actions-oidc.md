# GitHub Actions OIDC

## The problem with long-lived credentials in CI

The straightforward way to give a GitHub Actions workflow AWS access is to
store an IAM user's access key/secret as repo secrets. That's a long-lived
credential sitting in GitHub indefinitely - if it leaks (a misconfigured
log, a compromised action, a copy-pasted debug step), it's valid until
someone manually rotates it, and it typically carries whatever permissions
were convenient at setup time rather than exactly what one workflow run
needs.

A short-lived alternative that avoids storing credentials in GitHub at
all: temporarily export your own SSO session's short-lived keys as repo
secrets before each run (`aws sso login`, `aws configure
export-credentials`, `gh secret set`). Safer than a permanent key, but
manual, and every run is authenticated as *you* rather than as the
workflow itself.

## OIDC: the workflow authenticates as itself, with no stored secret

GitHub Actions can mint a short-lived, cryptographically signed OIDC token
for each job, scoped to that specific run (repo, ref, workflow). AWS STS
can be configured to trust that token directly via `sts:AssumeRoleWithWebIdentity`
- no AWS credential is ever stored in GitHub. Each run gets its own
temporary session credentials, minted just for that run and expiring with
it.

## Why this has to live in `bootstrap/`, not the main config

This role is what CI *authenticates with* to run `terraform apply` against
`terraform/`'s main config. If creating that role were also part of the
main config - the same thing CI applies - the first-ever CI run would need
the role to exist before it can authenticate to create the role in the
first place. Same chicken-and-egg shape as the state bucket itself
(Terraform needs a backend to store state in before it can manage
anything). Both get created once, by hand, with your own admin-level AWS
credentials, from `terraform/bootstrap/` - a separate, small, human-applied
config that the CI role itself never touches.

## How it's wired up here

`terraform/modules/github-oidc` creates two things, applied once from
`terraform/bootstrap/` (the same one-time, run-with-your-own-credentials
step that creates the Terraform state bucket):

1. An `aws_iam_openid_connect_provider` trusting
   `https://token.actions.githubusercontent.com` - the thumbprint is
   fetched live via the `tls_certificate` data source rather than
   hardcoded, so it never goes stale if GitHub rotates its TLS chain.
2. An IAM role whose trust policy allows `sts:AssumeRoleWithWebIdentity`
   from that provider, conditioned on the token's `sub` claim matching
   `repo:<owner>/<repo>:*` - scoped to this one repository, not any other
   repo under the same GitHub account. (Narrow this further to
   `repo:<owner>/<repo>:ref:refs/heads/main` if only the default branch
   should ever be allowed to apply/destroy infrastructure.)

The workflows (`.github/workflows/terraform-infra.yml`,
`terraform-lint.yml`) then use
[`aws-actions/configure-aws-credentials`](https://github.com/aws-actions/configure-aws-credentials)
with `role-to-assume: ${{ vars.AWS_OIDC_ROLE_ARN }}` instead of any
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` secrets. The role ARN itself
isn't sensitive (it can't be assumed without a valid GitHub-issued token
for this repo), so it's stored as a repo **variable**, not a secret. Each
job also needs `permissions: { id-token: write }` - that's the permission
that lets GitHub mint the OIDC token in the first place.

## What the CI role can actually do

`terraform/modules/github-oidc/ci-terraform-policy.json.tpl` grants what
this repo's Terraform config needs to manage its own resources: broad
access to the AWS services it provisions (EC2/VPC, EKS, ELB, Auto
Scaling, Route 53, ACM, CloudWatch Logs/Metrics), IAM actions scoped by
resource-name prefix to roles/policies this project creates
(`${cluster_name}*`), and S3 access scoped to the Terraform state bucket
specifically. It's broader than a textbook least-privilege policy - a
config that provisions a VPC and an EKS cluster from scratch fundamentally
needs create/delete rights on those services - but it's still narrower
than blanket `AdministratorAccess`, and none of it is reachable without a
valid, repo-scoped GitHub OIDC token in the first place.
