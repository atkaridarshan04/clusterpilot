resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    dex            = { enabled = false }
    notifications  = { enabled = false }
    applicationSet = { enabled = false }
    configs = {
      secret = {
        argocdServerAdminPassword = var.admin_password_bcrypt_hash
      }
    }
  })]
}

# Only created if a token was actually given - a public repo_url clones
# anonymously, and ArgoCD needs no credentials for that at all. See
# docs/concepts/gitops-with-argocd.md.
resource "kubernetes_secret" "repo_creds" {
  count = var.repo_token != "" ? 1 : 0

  metadata {
    name      = "clusterpilot-repo-creds"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.repo_url
    username = "git"
    password = var.repo_token
  }

  depends_on = [helm_release.argocd]
}


resource "kubectl_manifest" "app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "clusterpilot-k8s"
      namespace = "argocd"
      # Cascades terraform destroy through everything this Application
      # synced, instead of orphaning it - see docs/concepts/gitops-with-argocd.md.
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        path           = var.repo_path
        targetRevision = var.repo_revision
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd, kubernetes_secret.repo_creds]
}
