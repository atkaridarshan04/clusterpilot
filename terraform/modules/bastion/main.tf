# SSH ops box for kubectl access. View-only on purpose - see
# docs/concepts/irsa-and-pod-identity.md for why an instance role is scoped
# this tightly.

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  tags               = var.tags
}

data "aws_iam_policy_document" "describe_cluster" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [var.cluster_arn]
  }
}

resource "aws_iam_policy" "describe_cluster" {
  name        = "${var.cluster_name}-bastion-eks-describe"
  description = "Lets the bastion run `aws eks update-kubeconfig` for this cluster"
  policy      = data.aws_iam_policy_document.describe_cluster.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "describe_cluster" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.describe_cluster.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.cluster_name}-bastion"
  role = aws_iam_role.this.name
}

# RBAC side, separate from the IAM role above - View only.
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "bastion_view" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.cluster_name}-bastion"
  public_key = var.ssh_public_key
  tags       = var.tags
}

resource "aws_security_group" "this" {
  #checkov:skip=CKV_AWS_24:ssh_ingress_cidr is operator-restricted, not 0.0.0.0/0 - checkov can't resolve the variable value
  #checkov:skip=CKV_AWS_382:full outbound is intentional - bastion needs the EKS API and OS package repos
  name        = "${var.cluster_name}-bastion"
  description = "Ops bastion - SSH only, from ssh_ingress_cidr"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  egress {
    description = "EKS API/package repos - all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-bastion" })
}

# In-VPC resources resolve the cluster endpoint to its own ENIs regardless
# of public/private access, so this rule is needed either way.
resource "aws_security_group_rule" "bastion_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.this.id
  description              = "Bastion access to EKS API"
}

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88:bastion must be reachable directly over SSH from ssh_ingress_cidr, no other path in
  #checkov:skip=CKV_AWS_126:detailed monitoring's 1-min metrics aren't worth the per-instance cost for an ops bastion
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true
  ebs_optimized               = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    curl -LO "https://dl.k8s.io/release/v${var.kubernetes_version}.0/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  EOF

  tags = merge(var.tags, { Name = "${var.cluster_name}-bastion" })
}
