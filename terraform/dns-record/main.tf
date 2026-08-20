data "aws_route53_zone" "this" {
  name         = var.zone_name
  private_zone = false
}

# Matches tags the ALB controller puts on this Ingress's ALB - apply only
# after `kubectl apply` has created it.
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "ingress.k8s.aws/stack" = "${var.ingress_namespace}/${var.ingress_name}"
  }
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = false
  }
}
