data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Construct the S3 bucket ARN from the bucket name.
  s3_bucket_arn = "arn:aws:s3:::${var.s3_bucket_name}"

  common_tags = merge(
    {
      Creator = "terraform"
      Name    = var.lambda_function_name
    },
    var.tags
  )
}

# ---------------------------------------------------------------------------
# Lambda packaging
# ---------------------------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
}

# ---------------------------------------------------------------------------
# IAM role for the Lambda function
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = var.lambda_function_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda" {
  name = var.lambda_function_name
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read-only EC2 permissions to describe SGs and NACLs
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkAcls",
        ]
        Resource = "*"
      },
      {
        # Write permissions to the specified S3 bucket only
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${local.s3_bucket_arn}/*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "save_netpol" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda.arn
  handler       = "save_netpol.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  architectures    = var.lambda_architectures

  environment {
    variables = {
      S3_BUCKET_NAME = var.s3_bucket_name
      REGIONS        = join(",", var.regions)
    }
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler
#
# Uses the newer EventBridge Scheduler (aws_scheduler_schedule) instead of the
# legacy CloudWatch Events rule. The Scheduler needs its own execution role
# with permission to invoke the target Lambda function.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${var.lambda_function_name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.lambda_function_name}-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.save_netpol.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "backup" {
  name       = "${var.lambda_function_name}-schedule"
  group_name = var.schedule_group_name

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  description                  = "Triggers the ${var.lambda_function_name} Lambda to back up SGs and NACLs to S3."

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.save_netpol.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}
