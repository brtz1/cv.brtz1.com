variable "aws_region" {
  description = "Region for the S3 bucket (and default provider)."
  type        = string
  default     = "eu-south-2"
}

variable "domain_name" {
  description = "Root domain hosted in Route53."
  type        = string
  default     = "brtz1.com"
}

variable "subdomain" {
  description = "Subdomain for the CV site."
  type        = string
  default     = "cv"
}

variable "bucket_name" {
  description = "S3 bucket name that stores the website files."
  type        = string
  default     = "resume-static-website1"
}

variable "price_class" {
  description = "CloudFront price class (cheapest scope is PriceClass_100)."
  type        = string
  default     = "PriceClass_100"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table for the visit counter."
  type        = string
  default     = "cv-visitor-counter"
}

variable "lambda_name" {
  description = "Lambda function name for the visit counter API."
  type        = string
  default     = "cv-visitor-counter"
}

variable "cloudfront_web_acl_id" {
  description = "WAFv2 Web ACL ARN for CloudFront (global, us-east-1)."
  type        = string
  default     = "arn:aws:wafv2:us-east-1:173294455146:global/webacl/CreatedByCloudFront-8df85bb0/7eae0403-f581-4d99-aea4-b6a72d482d15"
}
