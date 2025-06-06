variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "chaos-engineering-demo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
