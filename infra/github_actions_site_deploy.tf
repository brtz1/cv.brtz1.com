data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    # GitHub's OIDC thumbprint is commonly this, but can change over time.
    # If you already manage this provider elsewhere, remove this resource
    # and reference the existing provider ARN in the role.
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

resource "aws_iam_role" "github_site_deploy" {
  name = "github-actions-site-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow ONLY workflows from this repo AND this GitHub Environment
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:environment:${var.github_environment}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_site_deploy" {
  name = "github-actions-site-deploy-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}"
        ]
      },
      {
        Sid    = "S3ObjectsRW"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = ["cloudfront:CreateInvalidation"]
        Resource = [
          "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.cdn.id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_site_deploy_attach" {
  role       = aws_iam_role.github_site_deploy.name
  policy_arn = aws_iam_policy.github_site_deploy.arn
}

output "github_site_deploy_role_arn" {
  value = aws_iam_role.github_site_deploy.arn
}
