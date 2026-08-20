# IRSA and Pod Identity

Every controller in this cluster that calls an AWS API (the ALB controller,
Cluster Autoscaler, the EBS CSI driver, the CloudWatch Observability addon)
needs AWS credentials scoped to exactly what it does - not the node's own
instance role, which every pod on that node could otherwise reach via the
EC2 metadata service.

## The problem: node-wide credentials are too broad

An EC2 instance profile's credentials are vended to any process on that
instance through the metadata service - there's no built-in check tying
them to a specific pod or workload. If every controller ran under the
node's own IAM role, any pod on that node - not just the intended
controller - could reach those same credentials. This is also why
`terraform/modules/bastion`'s IAM role is scoped to `AmazonEKSViewPolicy`
(read-only) rather than something broader, even though the bastion's whole
purpose is EKS access: whatever role is on the box, everything running on
that box inherits it.

Kubernetes needs a way to bind a specific IAM role to a specific pod,
independent of the node it lands on. There are two mechanisms for this on
EKS; this repo uses the newer one.

## EKS Pod Identity (used here)

Every addon role in this repo (`terraform/modules/pod-identity-role`) uses
**EKS Pod Identity**:

1. The `eks-pod-identity-agent` EKS addon runs on every node
   (`terraform/modules/eks/main.tf`).
2. An IAM role's trust policy allows `sts:AssumeRole` + `sts:TagSession`
   from the `pods.eks.amazonaws.com` service principal - no per-cluster
   OIDC provider/issuer involved at all
   (`terraform/modules/pod-identity-role/main.tf`).
3. An `aws_eks_pod_identity_association` resource links that role directly
   to a `(cluster, namespace, service_account)` triple - no annotation on
   the ServiceAccount object itself, no helm `set` for a role-arn
   annotation. The agent looks up the association and injects credentials
   at pod-start time.

Every addon module (`ingress-controller`, `eks-addons`,
`cluster-autoscaler`) calls `pod-identity-role` with its own role name,
namespace/service account, and policy ARNs, so each controller ends up
with a distinct role scoped to only the actions it needs - same
least-privilege shape as IRSA below, with less plumbing per role and no
cluster-level OIDC provider to manage at all
(`terraform/modules/eks/main.tf` sets `enable_irsa = false` accordingly).

It's a plain top-level module rather than folded into `modules/eks` itself
- `terraform-aws-modules/eks/aws` (the upstream module `modules/eks`
wraps) does have a native `addons.<name>.pod_identity_association` field,
but it only creates the *association*, not the IAM role itself, and it
only applies to things declared as EKS-managed addons in that module's own
`addons` map. Two of these four roles (`ebs-csi`,
`cloudwatch-observability`) are EKS addons and could in principle use it;
the other two (the ALB Controller, Cluster Autoscaler) are plain Helm
releases with no addon-map equivalent at all, so they could never use that
field regardless. Splitting would mean two different patterns for the same
concept, for no actual reduction in code - the IAM role still has to be
built by hand either way. One uniform module, called identically by all
four, was the simpler and more consistent choice.

## IRSA (the older mechanism, not used in this repo)

IAM Roles for Service Accounts (IRSA) solves the same problem via the
cluster's OIDC identity provider instead:

1. The EKS cluster exposes an OIDC issuer; an
   `aws_iam_openid_connect_provider` resource registers it with IAM.
2. A role's trust policy allows `sts:AssumeRoleWithWebIdentity` from that
   OIDC provider, conditioned on a specific
   `system:serviceaccount:<namespace>:<name>` subject claim.
3. The pod's ServiceAccount carries an `eks.amazonaws.com/role-arn`
   annotation; the built-in Pod Identity Webhook injects a projected
   service-account token and AWS SDK env vars based on that annotation.

IRSA remains the AWS-supported mechanism, and it's what every AWS
Helm chart/EKS addon has supported the longest - it just needs an
OIDC-provider resource and a per-role trust-policy condition that Pod
Identity doesn't. Pod Identity is the AWS-recommended default for new
work going forward specifically because it removes that OIDC/trust-policy
boilerplate; this repo adopted it fully once nothing was left depending on
the older mechanism.

## The bastion is a different pattern from either of these

`terraform/modules/bastion`'s EC2 instance role is **not** Pod Identity or
IRSA - it's a plain instance profile, because it's not a Kubernetes
workload, it's an EC2 box used for `kubectl` access. Its narrow scope
(`eks:DescribeCluster` plus an EKS access entry bound to
`AmazonEKSViewPolicy`) is the mitigation for the node-wide-credentials
problem described above: anyone with a shell on the bastion inherits
exactly "can look," never "can write," regardless of what they're doing on
the box. Admin-level cluster changes go through your own already-admin
`kubectl` context (granted via
`enable_cluster_creator_admin_permissions = true` on the cluster itself),
never through the bastion's identity.

`terraform/modules/agent-role` is different again - it's an IAM role
assumed by *you* (via `sts:AssumeRole` from your own caller identity), not
by a pod at all, since `agent/` runs on your own machine rather than
in-cluster. See `agent/README.md`.
