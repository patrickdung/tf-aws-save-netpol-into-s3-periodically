# save-netpol-to-s3

A Terraform module that periodically backs up all **Security Groups** and **Network ACLs** across one or more AWS regions to an S3 bucket as JSON files, using a scheduled AWS Lambda function triggered by Amazon EventBridge Scheduler.

## Architecture

```
EventBridge Scheduler (schedule) → Lambda (boto3, paginated) → temp keys → final keys in S3
```

Each backup run creates a timestamped directory under `{s3_base_folder_path}/{region}/netpol/` for each configured region (`s3_base_folder_path` is optional, defaults to bucket root):

```
s3://{bucket}/{s3_base_folder_path}/{region}/netpol/2026-08-16THHMMSS/security-groups.json
s3://{bucket}/{s3_base_folder_path}/{region}/netpol/2026-08-16THHMMSS/network-acls.json
```

The regions (e.g. `us-east-2`, `eu-central-1`) are provided via the `regions` variable. All regions share the same timestamp so they are grouped under one backup run. The Lambda is deployed in a single region but queries each configured region via boto3. `ec2.describe_*` calls are paginated, so large accounts are fully covered.

### Failure handling and markers

To guarantee that the final JSON files always contain a **complete** snapshot, each region's run writes to temporary keys first and only promotes them after **both** `DescribeSecurityGroups` and `DescribeNetworkAcls` succeed:

```
{timestamp}/.in-progress
{timestamp}/.tmp.security-groups.json
{timestamp}/.tmp.network-acls.json
{timestamp}/security-groups.json   ← promoted (server-side copy) only if complete
{timestamp}/network-acls.json
```

- On success, temp keys and `.in-progress` are deleted, leaving only the two final files.
- On failure for a region, partial state is removed and a `{timestamp}/.failed` JSON marker (with the error) is written; the remaining regions still run.

A `.failed` object never exists alongside valid final data, so the presence of `security-groups.json`/`network-acls.json` under a timestamp directory means the backup is complete for that region.

### Failure alerting (optional, on by default)

When `enable_s3_eventbridge = true` the module:

- Enables EventBridge notifications on the existing bucket (`aws_s3_bucket_notification { eventbridge = true }`).
- Adds an EventBridge rule matching `Object Created` events for keys ending in `/.failed` in this bucket.
- Publishes those events to an SNS topic (`<lambda_function_name>-alerts`). If `alert_email` is set, an email subscription is created; otherwise subscribe later (e.g. PagerDuty/Slack).

Set `enable_s3_eventbridge = false` if the bucket's notification config is managed elsewhere.

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.6 |
| AWS provider | ~> 5.100.0 |
| Archive provider | ~> 2.4 |

## Usage

### Direct Terraform

```hcl
module "save_netpol" {
  source = "./modules/save-netpol-to-s3"

  s3_bucket_name      = "my-backup-bucket"
  s3_base_folder_path = "network-backups"
  regions             = ["us-east-2", "eu-central-1"]
  schedule_expression = "rate(1 day)"
  alert_email         = "oncall@example.com"

  tags = {
    Environment = "prod"
  }
}
```

### Terragrunt

See `examples/terragrunt/terragrunt.hcl` for a complete example.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|--------|
| `s3_bucket_name` | Name of the S3 bucket where backups will be saved (bucket must already exist) | `string` | — |
| `s3_base_folder_path` | Base folder path inside the bucket, between the root and `{region}/netpol/…` (empty = bucket root) | `string` | `""` |
| `enable_s3_eventbridge` | Enable EventBridge notifications on the bucket for `.failed` failure alerting | `bool` | `true` |
| `alert_email` | Email to subscribe to the failure-alerts SNS topic (empty = no subscription) | `string` | `""` |
| `regions` | List of AWS regions to back up SGs and NACLs from | `list(string)` | — |
| `schedule_expression` | EventBridge Scheduler expression (e.g. `rate(1 day)`, `cron(0 2 * * ? *)`) | `string` | `rate(1 day)` |
| `schedule_timezone` | Timezone for the schedule expression (e.g. `UTC`, `Australia/Sydney`) | `string` | `UTC` |
| `schedule_group_name` | EventBridge Scheduler schedule group name | `string` | `default` |
| `lambda_function_name` | Name of the Lambda function | `string` | `save-netpol-to-s3` |
| `lambda_runtime` | Runtime for the Lambda function (must exist in the deployment region) | `string` | `python3.14` |
| `lambda_timeout` | Timeout in seconds for the Lambda function | `number` | `60` |
| `lambda_memory_size` | Memory size in MB for the Lambda function | `number` | `128` |
| `lambda_architectures` | Instruction set architecture for the Lambda function (`["arm64"]` or `["x86_64"]`) | `list(string)` | `["arm64"]` |
| `lambda_log_retention_days` | Retention in days for the Lambda CloudWatch log group | `number` | `14` |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `lambda_function_name` | Name of the Lambda function |
| `lambda_function_arn` | ARN of the Lambda function |
| `lambda_role_arn` | ARN of the IAM role used by the Lambda function |
| `scheduler_role_arn` | ARN of the IAM role used by EventBridge Scheduler to invoke the Lambda |
| `scheduler_schedule_name` | Name of the EventBridge Scheduler schedule |
| `scheduler_schedule_arn` | ARN of the EventBridge Scheduler schedule |
| `log_group_name` | Name of the Lambda CloudWatch log group (with retention) |
| `s3_eventbridge_enabled` | Whether EventBridge notifications were enabled on the S3 bucket |
| `failure_alerts_sns_topic_arn` | ARN of the SNS topic receiving backup-failure alerts (`null` when `enable_s3_eventbridge = false`) |

## IAM Permissions

The module creates a least-privilege IAM role for the Lambda with:

- `ec2:DescribeSecurityGroups` — read SGs
- `ec2:DescribeNetworkAcls` — read NACLs
- `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` on `{s3_bucket_arn}/*` — write final backups plus the staged temp→final commit and marker cleanup, scoped to the specified bucket only

The module also creates an **EventBridge Scheduler execution role** with:

- `lambda:InvokeFunction` on the Lambda function ARN — allows the Scheduler to invoke the Lambda

## S3 Bucket

This module does **not** create the S3 bucket. The bucket must already exist and its ARN passed via `s3_bucket_arn`.

## Manual Invocation

After deployment, you can trigger a backup immediately:

```bash
aws lambda invoke \
  --function-name save-netpol-to-s3 \
  /tmp/response.json
cat /tmp/response.json
```
