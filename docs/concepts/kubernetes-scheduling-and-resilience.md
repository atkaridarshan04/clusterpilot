# Kubernetes scheduling and resilience: HPA, PDB, and rollout strategy

Three independent mechanisms in `k8s/policies.yaml` and
`k8s/wordpress-mysql.yaml` are easy to conflate because they all affect
"how many pods are running, and when." Each governs a different trigger.

## HorizontalPodAutoscaler: scales replica count against load

The HPA on the `wordpress` Deployment targets 70% average CPU
**utilization against `resources.requests`, not `resources.limits`**. This
needs two things to actually work:

- `metrics-server` in-cluster (an EKS addon, enabled in
  `terraform/modules/eks/main.tf`) - without it, the HPA can't read pod CPU
  at all, and reports `FailedGetResourceMetric`.
- `resources.requests` actually set on the container
  (`k8s/wordpress-mysql.yaml`) - the percentage target is meaningless
  against an unset request, since there's nothing to compute a percentage
  of.

The HPA's `behavior.scaleDown.stabilizationWindowSeconds` (shortened to
60s here from the 5-minute default) controls how long it waits, taking the
*highest* recent recommendation, before scaling back down - see
[cluster-autoscaling-and-pod-capacity.md](cluster-autoscaling-and-pod-capacity.md)
for how this interacts with Cluster Autoscaler's own, separate cooldown.

## PodDisruptionBudget: protects against *voluntary* evictions only

A PDB constrains voluntary disruptions specifically - `kubectl drain`,
Cluster Autoscaler scale-down, node upgrades. It has no say over anything
else, including a `Deployment` rollout (see below) or a node simply
crashing.

`k8s/policies.yaml` sets `minAvailable: 1` for `wordpress` only, not for
`mysql`. This is deliberate: `mysql` is a single-replica `StatefulSet`
(`replicas: 1`), and a `minAvailable: 1` PDB on a single-replica workload
doesn't protect anything - it just guarantees the PDB can never be
satisfied by evicting the only pod, which blocks *every* voluntary
disruption (drains, upgrades) indefinitely. A PDB is only meaningful once
there's a spare replica to shift load to, which is why `wordpress` (scaled
2-4 by its HPA) gets one and `mysql` doesn't.

## `strategy` governs rollouts - a PDB does not

Replacing pods with a new template (a `kubectl apply` that changes the
image, env, or any other pod-spec field) is governed entirely by the
Deployment's own `spec.strategy` - a completely separate mechanism from
the PDB above, which has no say in it at all. `k8s/wordpress-mysql.yaml`
uses `RollingUpdate` with `maxUnavailable: 1`, deliberately matching the
PDB's own `minAvailable: 1` so the two independent mechanisms - eviction
protection and rollout pacing - agree on "at least one pod up," even
though neither one is aware of the other.

(`Recreate`, the other built-in strategy, kills every existing pod before
creating any replacement - appropriate only when replicas can't coexist,
e.g. around a single shared `ReadWriteOnce` volume. See
[storage-and-statefulsets.md](storage-and-statefulsets.md) for why this
app doesn't have that constraint.)

## Container security context: privilege drop, not escalation

`k8s/wordpress-mysql.yaml` sets `allowPrivilegeEscalation: false` and
`seccompProfile: RuntimeDefault` on both containers, but deliberately
**not** `runAsNonRoot: true` or `capabilities.drop: ["ALL"]`. Both stock
images' entrypoints need to start as root: MySQL's entrypoint `chown`s the
mounted volume to the `mysql` user before `exec`-ing `mysqld` as that user;
WordPress's (Apache) does the same for `/var/www/html` and binds port 80,
a privileged port. Both drop to a non-root user internally once past that
setup step - a privilege *drop* (`setuid`/`setgid` from an already-root
process), which is not blocked by `allowPrivilegeEscalation: false` or a
seccomp profile, so both of those are safe to set unconditionally.
Setting `runAsNonRoot`/`capabilities.drop` up front instead would remove
the root/capabilities the entrypoint needs *before* it has a chance to
drop them itself, breaking startup (`chown`/bind fails with `EPERM`).
Hardening this further would need an init container to pre-`chown` the
volume (and, for WordPress, either an unprivileged port + Service remap,
or explicitly re-adding `CAP_NET_BIND_SERVICE`).
