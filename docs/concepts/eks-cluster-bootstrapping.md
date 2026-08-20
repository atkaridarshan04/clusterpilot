# EKS cluster bootstrapping: the same-apply chicken-and-egg

Provisioning a VPC, an EKS cluster, and Kubernetes-native controllers
(ArgoCD, in this repo) in one Terraform config runs into a structural
problem on the very first `apply`: some providers need the cluster's real
API endpoint/credentials to configure *themselves*, and those outputs
don't exist until the cluster itself has already been created - in the
same run that's supposed to create it.

## Why this shows up specifically with the `kubectl`/`kubernetes` providers

`terraform/modules/argocd`'s `kubectl_manifest.app` (the ArgoCD
`Application` object) uses the `alekc/kubectl` provider. Its provider
configuration (`host`/`token`/`cluster_ca_certificate`, sourced from
`module.eks`'s outputs in `terraform/providers.tf`) is validated eagerly:
on a cold start, before the cluster exists, those outputs are unknown, and
the provider fails outright with `invalid provider configuration: no
configuration has been provided`. This is provider-specific behavior, not
a general Terraform rule - the official `helm`/`kubernetes` providers
tolerate the same "not real yet" outputs fine, which is why
`ingress-controller`/`cluster-autoscaler` (both helm releases) don't hit
this.

## The fix: target the VPC/EKS layer first, on a cold start only

```
terraform plan  -target=module.vpc -target=module.eks
terraform apply -target=module.vpc -target=module.eks

terraform plan
terraform apply
```

The first, targeted apply makes the cluster (and the VPC it needs) real,
so its outputs are concrete by the time the full apply configures the
`kubectl`/`kubernetes`/`helm` providers. Both `module.vpc` and `module.eks`
need targeting explicitly, not just `module.eks` alone - targeting only
the cluster pulls in *just* the specific VPC outputs it directly
references (`vpc_id`, private/intra subnets), not the NAT gateway/IGW/
public subnets nodes need for internet egress, since nothing in
`module.eks` references those directly.

This two-step apply is a no-op on every apply after the first, once both
already exist - safe to always run in that order (see
`terraform/README.md` step 2, and the same sequence mirrored in
`.github/workflows/terraform-infra.yml`'s `apply` job).

## Why `plan` can't use the same trick

The targeted-first fix works for `apply` because that step actually
*applies* `module.vpc`/`module.eks` for real. `terraform plan` never
applies anything, so on a from-scratch account (no cluster yet), an
untargeted "plan everything" will always hit this same provider error, no
matter how the steps are ordered or retried. On a fresh account, `plan`
can only ever preview the vpc+eks layer; previewing anything downstream
of the cluster requires the cluster to actually exist first, i.e. running
`apply` at least once. The CI `plan` job tolerates *only* this specific,
known failure (checking for both `invalid provider configuration` and
`kubectl` in the error) and still fails the job for anything else.
