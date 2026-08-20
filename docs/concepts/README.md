# Concepts

Background for the non-obvious decisions baked into this repo - what each
mechanism is, why it applies here, and where to see it in the code. Written
as reference material, not a changelog: each doc explains the concept as it
stands today, not the sequence of attempts that led here.

- [Cluster autoscaling and pod capacity](cluster-autoscaling-and-pod-capacity.md) -
  why pods-per-node is capped by ENI/IP count, Cluster Autoscaler vs
  Karpenter, and how HPA/CA cooldowns interact.
- [IRSA and Pod Identity](irsa-and-pod-identity.md) - how pods get scoped AWS
  credentials, and why this repo uses IRSA.
- [GitHub Actions OIDC](github-actions-oidc.md) - how CI authenticates to AWS
  without long-lived credentials.
- [EKS cluster bootstrapping](eks-cluster-bootstrapping.md) - the
  chicken-and-egg problem of provisioning a cluster and its in-cluster
  controllers in one Terraform apply.
- [ALB networking and NetworkPolicy](alb-networking-and-network-policy.md) -
  how the AWS Load Balancer Controller wires traffic in, and why
  NetworkPolicy needs an explicit opt-in on EKS.
- [Storage and StatefulSets](storage-and-statefulsets.md) - EBS vs EFS,
  `volumeClaimTemplates` vs a shared PVC, and why the demo app has no PVC on
  its stateless tier.
- [Kubernetes scheduling and resilience](kubernetes-scheduling-and-resilience.md) -
  how HPA, PodDisruptionBudget, and rollout `strategy` are three independent
  mechanisms that are easy to conflate.
- [GitOps with ArgoCD](gitops-with-argocd.md) - sync/selfHeal/prune, and how
  teardown cascades through a synced Application.
- [Policy as code: checkov and tflint](policy-as-code-checkov-tflint.md) -
  what each tool actually checks, and how to record an intentional
  exception.
- [MCP and the cluster agent](mcp-agent-architecture.md) - what the Model
  Context Protocol is and how `agent/` uses it to give an LLM real,
  read-only access to a live cluster.
