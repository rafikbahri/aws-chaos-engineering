output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_url" {
  description = "URL of the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "fis_experiment_stop_instances_id" {
  description = "FIS experiment template ID for stopping instances"
  value       = aws_fis_experiment_template.stop_instances.id
}

output "fis_experiment_cpu_stress_id" {
  description = "FIS experiment template ID for CPU stress"
  value       = aws_fis_experiment_template.cpu_stress.id
}

output "cloudwatch_alarm_arn" {
  description = "CloudWatch alarm ARN used as stop condition"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "target_group_arn" {
  description = "Target group ARN for health checks"
  value       = aws_lb_target_group.web.arn
}