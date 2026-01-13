locals {
  zone_name      = "var.domain_name"
  subdomain_fqdn = "${var.subdomain}.${var.domain_name}"
  bucket_name    = "resume-static-website1"
}

############################
# Route53 Hosted Zone
############################
data "aws_route53_zone" "root" {
  provider     = aws.use1
  name         = var.domain_name
  private_zone = false
}

############################
# ACM Wildcard Cert (existing) in us-east-1
############################
data "aws_acm_certificate" "wildcard" {
  provider    = aws.use1
  domain      = "*.brtz1.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

############################
# S3 bucket (private) in eu-south-2
############################
resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################
# CloudFront OAC + Distribution
############################
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "cv.brtz1.com-oac"
  description                       = "OAC for cv.brtz1.com -> S3 private bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# While iterating, disabling caching prevents “old site still served” surprises
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "cv.brtz1.com"
  default_root_object = "index.html"
  price_class         = PriceClass_All
  tags = {
    Name = "cv.brtz1.com"
  }

  aliases = [local.subdomain_fqdn]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.site.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id

    s3_origin_config {
      # Required block; OAC is used (not OAI), so keep it empty
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  web_acl_id = var.cloudfront_web_acl_id
}

# Bucket policy allowing only this CloudFront distribution (OAC) to read objects
data "aws_iam_policy_document" "site_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudfront::173294455146:distribution/${aws_cloudfront_distribution.cdn.id}"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket_policy.json
}

############################
# Route53 records for cv.brtz1.com (existing A/AAAA)
############################
resource "aws_route53_record" "cv_a" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "cv.brtz1.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cv_aaaa" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "cv.brtz1.com"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

############################
# DynamoDB (us-east-1)
############################
resource "aws_dynamodb_table" "counter" {
  provider     = aws.use1
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

########################################
# IAM Role (existing): VisitorCounter
########################################
resource "aws_iam_role" "visitor_counter" {
  name        = "VisitorCounter"
  description = "Allows Lambda functions to call AWS services on your behalf."

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Managed policy attachment (existing)
resource "aws_iam_role_policy_attachment" "visitor_counter_basic" {
  role       = aws_iam_role.visitor_counter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline policy (existing): VisitorCounterDB
resource "aws_iam_role_policy" "visitor_counter_db" {
  name = "VisitorCounterDB"
  role = aws_iam_role.visitor_counter.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid      = "DynamoCounterRW",
      Effect   = "Allow",
      Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"],
      Resource = "arn:aws:dynamodb:us-east-1:173294455146:table/cv-visitor-counter"
    }]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_package.zip"
}

resource "aws_lambda_function" "counter" {
  provider      = aws.use1
  function_name = var.lambda_name
  role          = aws_iam_role.visitor_counter.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.14"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.counter.name
      COUNTER_ID     = local.subdomain_fqdn
      ALLOWED_ORIGIN = "https://${local.subdomain_fqdn}"
    }
  }
}

resource "aws_lambda_function_url" "counter" {
  provider           = aws.use1
  function_name      = aws_lambda_function.counter.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_headers     = ["content-type"]
    allow_methods     = ["GET", "POST"]
    allow_origins     = ["https://${local.subdomain_fqdn}"]
    max_age           = 86400
  }
}
