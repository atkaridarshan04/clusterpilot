# Cluster autoscaling and pod capacity

## Pods-per-node is capped by networking, not compute

EKS derives the maximum number of pods a node can run from the instance
type's ENI (Elastic Network Interface) count and secondary-IP-per-ENI limit
- a fixed number looked up from the instance type, completely independent
of `resources.requests`/`resources.limits`. A node can report plenty of
free CPU and memory and still refuse to schedule another pod.

This matters in practice because the kube-system daemonsets/addons this
cluster runs (`aws-node`, `kube-proxy`, `ebs-csi-node`, plus one replica
each of `coredns`, `metrics-server`, `ebs-csi-controller`,
`aws-load-balancer-controller`) already consume several pod slots on every
node before a single application pod is scheduled. On a small instance
type this can exhaust the pod budget entirely - the symptom is
`0/N nodes are available: N Too many pods`, with app pods stuck `Pending`
while `kubectl top nodes` shows headroom.

Check actual pod capacity before assuming a scheduling failure is
resource-pressure related:

```
kubectl get nodes -o custom-columns=NAME:.metadata.name,ALLOCATABLE_PODS:.status.allocatable.pods
```

This repo's node group (`terraform/locals.tf`) uses `t3a.medium` for
enough headroom above the daemonset floor.

## `min`/`max`/`desired` are static bounds, not a control loop

A node group's `min_size`/`max_size`/`desired_size` only define the range
an Auto Scaling Group is allowed to sit in - nothing watches for `Pending`
pods and reacts on its own. Without a separate autoscaling controller,
`max_size: 10` is a ceiling nothing ever climbs toward.

`terraform/modules/cluster-autoscaler` installs Kubernetes Cluster
Autoscaler (via helm, with its own IRSA role) to close that loop: it
watches for unschedulable pods and raises `desired_size` on the existing
ASG, within its configured bounds.

One Terraform-specific wrinkle: the upstream
`terraform-aws-modules/eks` module sets
`lifecycle { ignore_changes = [scaling_config[0].desired_size] }` on the
managed node group, deliberately, so a running autoscaler doesn't fight
Terraform over node count on every apply. Practical effect: editing
`node_desired_size` in `locals.tf` only affects a **freshly created** node
group. To change the desired size of an existing one, use the AWS API
directly:

```
aws eks update-nodegroup-config \
  --cluster-name clusterpilot --nodegroup-name <name> \
  --scaling-config minSize=3,maxSize=10,desiredSize=3
```

## Cluster Autoscaler vs Karpenter

Both watch for unschedulable pods and provision capacity in response; the
difference is what they provision it *through*.

- **Cluster Autoscaler** (used here) scales the `desired_size` of an
  existing ASG-backed managed node group, within its `min`/`max`. Minimal
  architecture change on top of a standard managed node group - one IRSA
  role, one helm release. Limitation: it can only add more of whatever
  instance type(s) the node group already has, so it doesn't help with the
  pod-density ceiling above - it just adds more nodes at the same density.
- **Karpenter** provisions EC2 instances directly, with no ASG/node group
  in the loop, choosing instance type and size based on the actual pending
  pods' requirements. Better bin-packing, and can genuinely raise
  pod density by picking a larger instance instead of cloning small ones.
  Cost: it wants to own node lifecycle itself (its own node IAM role,
  `NodePool`/`EC2NodeClass` CRDs, typically an SQS interruption queue for
  spot) - materially more moving parts.

Cluster Autoscaler is the lower-friction fit for an existing ASG-backed
node group at this scale. Karpenter is worth revisiting specifically if
pod *density* (not just node count) becomes the actual bottleneck.

## Two independent scale-down cooldowns stack

Scaling down is deliberately slow, and it's slow for two unrelated reasons
stacked on top of each other:

- **HPA**: `scaleDown.stabilizationWindowSeconds` (default 5 minutes,
  shortened to 60s in `k8s/policies.yaml` for faster feedback in this demo)
  makes the HPA take the *highest* replica recommendation from that window
  before scaling down - avoids flapping on a noisy metric.
- **Cluster Autoscaler**: a node has to sit continuously "unneeded" for
  `scale-down-unneeded-time` (default 10m, set to 3m here) *and* there's a
  separate global cooldown, `scale-down-delay-after-add` (also 10m/3m
  here) - no scale-down cluster-wide until that long after the last
  scale-up. Whichever condition clears last is what actually gates the
  node removal.

Treat these as two independent timers you can tune separately, not one
setting.
