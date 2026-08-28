output "lambda_function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.save_netpol.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function."
  value       = aws_lambda_function.save_netpol.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function."
  value       = aws_iam_role.lambda.arn
}

output "scheduler_role_arn" {
  description = "ARN of the IAM role used by EventBridge Scheduler to invoke the Lambda."
  value       = aws_iam_role.scheduler.arn
}

output "scheduler_schedule_name" {
  description = "Name of the EventBridge Scheduler schedule."
  value       = aws_scheduler_schedule.backup.name
}

output "scheduler_schedule_arn" {
  description = "ARN of the EventBridge Scheduler schedule."
  value       = aws_scheduler_schedule.backup.arn
}

output "log_group_name" {
  description = "Name of the Lambda CloudWatch log group (with retention)."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "s3_eventbridge_enabled" {
  description = "Whether the module enabled EventBridge notifications on the S3 bucket."
  value       = var.enable_s3_eventbridge
}

output "failure_alerts_sns_topic_arn" {
  description = "ARN of the SNS topic that receives backup-failure alerts (null when enable_s3_eventbridge is false)."
  value       = var.enable_s3_eventbridge ? aws_sns_topic.failure_alerts[0].arn : null
}
