# ALB networking and NetworkPolicy

## How a request reaches a pod

`k8s/ingress.yaml.tpl` (rendered to `k8s/ingress.yaml` by Terraform with
the real ACM cert ARN, and applied directly rather than via ArgoCD - see
[gitops-with-argocd.md](gitops-with-argocd.md)) is a standard Kubernetes
`Ingress` with `alb.ingress.kubernetes.io/*` annotations. The AWS Load
Balancer Controller (`terraform/modules/ingress-controller`) watches for
these and provisions a real Application Load Balancer outside of
Terraform's view entirely - it's created dynamically by the controller at
`kubectl apply` time, never a Terraform resource. `target-type: ip` means
the ALB routes directly to pod IPs, bypassing kube-proxy/Service routing
entirely - which is why NetworkPolicy rules for this Ingress's traffic
have no in-cluster source to scope to (see below).

## The ALB controller's own security group is invisible to Kubernetes

With `target-type: ip`, the controller auto-manages a security group on
each target pod's ENI, allowing the target port only from the ALB's own
security group. This is enforced entirely at the AWS networking layer -
no NetworkPolicy object, no Kubernetes API visibility - and it silently
drops non-matching traffic rather than refusing it. Practical consequence:
load-testing an app behind this kind of Ingress has to originate either
from inside the pod itself (`kubectl exec ... curl localhost`) or through
the real ALB endpoint - traffic from another in-cluster pod hitting the
Service or pod IP directly will simply time out, which can look
indistinguishable from a NetworkPolicy problem unless you know to check
for this SG separately from anything `kubectl get networkpolicy` shows.

## The controller's admission webhook affects every Service, not just Ingress

The AWS Load Balancer Controller registers a cluster-wide mutating webhook
for *all* `Service` creation (`mservice.elbv2.k8s.aws`), not just ones
tied to an Ingress. Anything that creates a Service - including an
unrelated EKS addon's own internal Service - gets intercepted by that
webhook, and fails if the controller's own pods aren't Ready yet to serve
it. In this repo, `module.eks_addons` (which creates the CloudWatch
Observability addon's Service objects) explicitly `depends_on
[module.ingress_controller]` for exactly this reason, and
`kubectl_manifest.ingress` in `terraform/main.tf` does the same. Anything
that creates a `Service`/`Ingress` object in this cluster should be
ordered after the controller is actually serving, not just scheduled.

## NetworkPolicy needs an explicit opt-in on EKS's default CNI

`NetworkPolicy` objects apply cleanly against the default `vpc-cni` addon
configuration and enforce **nothing** - no error, no warning, just a
silent no-op, because the CNI's node agent doesn't program the underlying
eBPF rules unless told to. `terraform/modules/eks/main.tf` sets
`enableNetworkPolicy: "true"` in the `vpc-cni` addon's
`configuration_values` specifically so the default-deny + explicit-allow
rules in `k8s/policies.yaml` actually take effect. Always verify
enforcement, not just that the objects applied without error:

```
kubectl get networkpolicy
```

applying successfully is not evidence anything is actually being enforced
on this CNI.
