# GitOps with ArgoCD

## What ArgoCD owns here

`terraform/modules/argocd` installs ArgoCD (a lightweight profile - no
Dex/SSO, notifications, or ApplicationSet controller, none of which this
project needs) and a single bootstrap `Application` pointing at this
repo's `k8s/` directory, with `syncPolicy.automated.prune` and `.selfHeal`
both on. From that point on, `k8s/storageclass.yaml`,
`k8s/wordpress-mysql.yaml`, `k8s/policies.yaml`, and
`k8s/event-exporter.yaml` are ArgoCD's responsibility - committing a
change to any of them is the deploy mechanism, not `kubectl apply`.

`k8s/ingress.yaml` is the deliberate exception: its cert ARN is only known
at Terraform-apply time, so it's rendered locally by Terraform
(`local_file.ingress_manifest` in `terraform/main.tf`) and applied
directly (`kubectl_manifest.ingress`), then gitignored. ArgoCD only ever
syncs what's committed to git, so a gitignored file is simply invisible to
it - not an exception it has to be told about.

## selfHeal means git is the only way to change synced state

With `selfHeal` on, a manual `kubectl apply`/`kubectl delete` against any
ArgoCD-managed object gets reverted automatically the next reconcile loop
- ArgoCD sees the drift from what's in git and corrects it. This is a
feature, not friction: it's what makes "commit a change, it deploys
itself" actually reliable rather than aspirational. The practical
consequence is that debugging by directly `kubectl edit`-ing a synced
object won't hold - go through git instead, or temporarily pause sync if
you genuinely need to poke at live state.

## Directory sources sync everything in the path, not a curated list

`module.argocd`'s `Application` points at the whole `k8s/` directory with
no file filtering - it doesn't just sync the files a comment or README
might describe as "the important ones," it syncs every manifest in that
directory that's actually committed to git.
`kubectl get application clusterpilot-k8s -n argocd -o jsonpath=...` is
the way to see the real, current list of managed resources - not an
assumption from reading the directory listing.

## Teardown: the Application's finalizer is what cascades deletion

By default, deleting an ArgoCD `Application` object only removes ArgoCD's
own bookkeeping - it orphans whatever that Application was syncing rather
than deleting it. Setting
`metadata.finalizers = ["resources-finalizer.argocd.argoproj.io"]` on the
Application (`terraform/modules/argocd/main.tf`) makes that object's
deletion block until ArgoCD's controller has actually cascaded the delete
through every resource it manages. This is what lets `terraform destroy`
(which deletes the Application as part of tearing down `module.argocd`)
clean up everything ArgoCD-managed on its own - no separate manual
`kubectl delete -f k8s/` step needed, for anything except the gitignored
`ingress.yaml`, which was never ArgoCD's to manage in the first place.
