output "site_url" {
  value = "https://cv.brtz1.com"
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "lambda_function_url" {
  value = aws_lambda_function_url.counter.function_url
}

output "dynamodb_table" {
  value = aws_dynamodb_table.counter.name
}
