output "ec2_instance_id" {
  description = "ID of the EC2 instance publishing metrics."
  value       = aws_instance.telemetry.id
}

output "iot_thing_name" {
  description = "Logical IoT thing representing the EC2 telemetry source."
  value       = aws_iot_thing.ec2_metrics_source.name
}

output "iot_topic" {
  description = "AWS IoT Core topic that receives the EC2 metrics payloads."
  value       = local.metrics_topic
}

output "iot_data_endpoint" {
  description = "Data endpoint used by the EC2 instance when publishing metrics."
  value       = data.aws_iot_endpoint.data.endpoint_address
}

output "metrics_table_name" {
  description = "DynamoDB table storing the ingested telemetry."
  value       = aws_dynamodb_table.metrics.name
}

output "ssm_start_session_command" {
  description = "Command to connect to the EC2 instance with AWS Systems Manager Session Manager."
  value       = "aws ssm start-session --target ${aws_instance.telemetry.id} --region ${data.aws_region.current.region}"
}

output "metrics_api_url" {
  description = "Base URL for the HTTP API that returns telemetry records."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "frontend_bucket_name" {
  description = "S3 bucket that hosts the Angular static website."
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_website_url" {
  description = "Public website URL for the S3-hosted Angular frontend."
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "frontend_deploy_command" {
  description = "Command to upload the Angular production build to the S3 website bucket."
  value       = "aws s3 sync ../frontend/dist/telemetry-web/browser s3://${aws_s3_bucket.frontend.bucket} --delete"
}