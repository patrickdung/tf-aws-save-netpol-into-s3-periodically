variable "s3_bucket_name" {
  description = "The name of the S3 bucket where SG and NACL backups will be saved. The bucket must already exist."
  type        = string
}

variable "regions" {
  description = "List of AWS regions to back up Security Groups and Network ACLs from. Each region's data is saved under {region}/netpol/{timestamp}/ in the S3 bucket."
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

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
