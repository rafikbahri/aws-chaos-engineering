resource "aws_cloudwatch_log_group" "fis_logs" {
  name              = "/aws/fis/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-fis-logs"
    Environment = var.environment
  }
}
