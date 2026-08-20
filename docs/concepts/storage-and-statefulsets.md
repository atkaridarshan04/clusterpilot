# Storage and StatefulSets

## `Deployment` volumes are one shared template, not per-replica

A `Deployment`'s pod template is copied verbatim for every replica,
including `volumes[].persistentVolumeClaim.claimName` - there is no
per-replica volume templating. N replicas of a Deployment that references
a PVC all mount the *literal same* volume. `StatefulSet` exists
specifically to solve this: `volumeClaimTemplates` mints a uniquely-named
PVC per replica (`mysql-persistent-storage-mysql-0`, `-1`, ...), which is
why `k8s/wordpress-mysql.yaml` runs MySQL as a `StatefulSet`.

## Why this matters once replicas land on different nodes

The scheduler places pods based on CPU/memory/pod-count fit - it has no
concept of "is this specific EBS volume already attached elsewhere."
That's checked later, at actual attach time, by the attach-detach
controller calling the EBS CSI driver. A plain `ReadWriteOnce` (RWO) EBS
volume can only be attached to one EC2 instance at a time; if a second
node's pod tries to mount the same one, the `AttachVolume` call itself
fails, surfacing as `FailedAttachVolume: Multi-Attach error` on a pod that
otherwise scheduled without complaint. (The newer `ReadWriteOncePod`
access mode *is* checked by the scheduler up front, for exactly this
reason - plain `ReadWriteOnce` is not.)

This is why `k8s/wordpress-mysql.yaml`'s WordPress `Deployment` has no PVC
at all, even though the upstream image supports one: WordPress scales via
HPA to multiple replicas (`k8s/policies.yaml`), and a shared RWO volume
across replicas on different nodes hits the Multi-Attach failure above.
The only thing on that volume that would need persistence is
`wp-content/uploads`, and a shared RWO PVC was already broken for
correctness with >1 replica regardless of the attach error: an upload
only lands on whichever pod handled that request, and the ALB
round-robining a later request to a different replica would show a broken
image either way. WordPress's own core files regenerate from the image on
every container start, and the durable state that actually matters (posts,
users, config) lives in MySQL's PVC - nothing about WordPress itself
depends on having a volume.

## RWX is a different kind of storage, not a flag on the same volume

`accessModes: [ReadWriteMany]` (RWX) is a request the storage backend has
to actually implement - not a setting that unlocks a capability on an
existing EBS volume. EBS is network-attached block storage that AWS only
ever lets one instance attach to at a time; there's no flag that changes
this, because it's a physical/API-level property of block storage itself,
not a Kubernetes-side restriction. Genuine RWX needs a network filesystem
underneath - on AWS that's EFS (`efs.csi.aws.com`) or FSx. Setting
`ReadWriteMany` against the `gp3` (`ebs.csi.aws.com`) `StorageClass` in
`k8s/storageclass.yaml` wouldn't silently degrade to something else; the
PVC would simply fail to provision.

## If this app needed a shared writable volume

Re-enable the commented-out `PersistentVolumeClaim` in
`k8s/wordpress-mysql.yaml` (and its `volumeMounts`/`volumes` entries) only
after switching to an RWX-capable backend such as EFS - re-adding it
against the current `gp3`/EBS `StorageClass` would reintroduce the
Multi-Attach failure the moment a second replica schedules onto a
different node.
