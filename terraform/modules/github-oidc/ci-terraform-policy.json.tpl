{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InfraServicesThisConfigManages",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "elasticloadbalancing:*",
        "autoscaling:*",
        "route53:*",
        "acm:*",
        "ecr:*",
        "ssm:*",
        "logs:*",
        "rds:*",
        "dynamodb:*",
        "kms:*",
        "cloudwatch:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForProjectScopedRoles",
      "Effect": "Allow",
      "Action": "iam:*",
      "Resource": [
        "arn:aws:iam::*:role/${name}*",
        "arn:aws:iam::*:instance-profile/${name}*",
        "arn:aws:iam::*:policy/*${name}*"
      ]
    },
    {
      "Sid": "ServiceLinkedRolesForServicesThisConfigUses",
      "Effect": "Allow",
      "Action": "iam:*",
      "Resource": "arn:aws:iam::*:role/aws-service-role/*"
    },
    {
      "Sid": "IamReadOnAnyPolicy",
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:GetPolicyVersion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateBucket",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "${state_bucket_arn}",
        "${state_bucket_arn}/*"
      ]
    }
  ]
}
