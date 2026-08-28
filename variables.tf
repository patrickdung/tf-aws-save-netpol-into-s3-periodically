variable "s3_bucket_name" {
  description = "The name of the S3 bucket where SG and NACL backups will be saved. The bucket must already exist."
  type        = string
}

variable "s3_base_folder_path" {
  description = "Optional base folder path inside the S3 bucket, between the bucket root and the region directory. Final backup keys are {s3_base_folder_path}/{region}/netpol/{timestamp}/. Leave empty to store at the bucket root. Leading/trailing slashes are trimmed automatically."
  type        = string
  default     = ""
}

variable "enable_s3_eventbridge" {
  description = "Whether the module enables EventBridge notifications on the S3 bucket (aws_s3_bucket_notification with eventbridge = true). Required for failure alerting via the .failed markers. Set to false if the bucket's notification configuration is managed elsewhere."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Optional email address to subscribe to the failure-alert SNS topic. Leave empty to create the topic without a subscription (you can subscribe later, e.g. via PagerDuty/Slack integrations)."
  type        = string
  default     = ""
}

variable "regions" {
  description = "List of AWS regions to back up Security Groups and Network ACLs from. Each region's data is saved under {s3_base_folder_path}/{region}/netpol/{timestamp}/ in the S3 bucket."
  type        = list(string)
}

variable "schedule_expression" {
  description = "EventBridge Scheduler schedule expression for the backup Lambda (e.g. 'rate(1 day)', 'cron(0 2 * * ? *)')."
  type        = string
  default     = "rate(1 day)"
}

variable "schedule_timezone" {
  description = "Timezone in which the schedule expression is evaluated. Defaults to UTC. See https://docs.aws.amazon.com/scheduler/latest/UserGuide/schedule-types.html"
  type        = string
  default     = "UTC"
}

variable "schedule_group_name" {
  description = "Name of the EventBridge Scheduler schedule group. Defaults to the 'default' group."
  type        = string
  default     = "default"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function."
  type        = string
  default     = "save-netpol-to-s3"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function."
  type        = string
  default     = "python3.14"
}

variable "lambda_timeout" {
  description = "Timeout in seconds for the Lambda function."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Memory size in MB for the Lambda function."
  type        = number
  default     = 128
}

variable "lambda_architectures" {
  description = "Instruction set architecture for the Lambda function. Valid values: [\"arm64\"] or [\"x86_64\"]. Defaults to arm64 (Graviton)."
  type        = list(string)
  default     = ["arm64"]
}

variable "lambda_log_retention_days" {
  description = "Retention in days for the Lambda function's CloudWatch log group."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
