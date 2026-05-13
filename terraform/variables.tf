variable "aws_region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for all provisioned resources."
  type        = string
  default     = "ec2-iot-demo"
}

variable "instance_type" {
  description = "EC2 instance type for the metrics publisher."
  type        = string
  default     = "t3.micro"
}

variable "telemetry_interval_seconds" {
  description = "How often the EC2 instance publishes metrics to AWS IoT Core."
  type        = number
  default     = 60
}

variable "vpc_cidr" {
  description = "CIDR block for the example VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet used by the EC2 instance."
  type        = string
  default     = "10.42.1.0/24"
}

variable "api_allowed_origins" {
  description = "Origins allowed to call the API Gateway endpoint from the frontend."
  type        = list(string)
  default     = ["*"]
}

variable "api_default_query_limit" {
  description = "Default number of telemetry records returned by the read API."
  type        = number
  default     = 20
}