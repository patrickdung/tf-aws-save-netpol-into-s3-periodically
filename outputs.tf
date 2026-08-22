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
