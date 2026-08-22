# save-netpol-to-s3

A Terraform module that periodically backs up all **Security Groups** and **Network ACLs** across one or more AWS regions to an S3 bucket as JSON files, using a scheduled AWS Lambda function triggered by Amazon EventBridge Scheduler.

## Architecture

```
EventBridge Scheduler (schedule) → Lambda (boto3) → S3
```

Each backup run creates a timestamped directory under `{region}/netpol/` for each configured region:

```
s3://{bucket}/{region}/netpol/2026-08-16THHMMSS/security-groups.json
s3://{bucket}/{region}/netpol/2026-08-16THHMMSS/network-acls.json
```

The regions (e.g. `us-east-2`, `eu-central-1`) are provided via the `regions` variable. All regions share the same timestamp so they are grouped under one backup run. The Lambda is deployed in a single region but queries each configured region via boto3.

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
  regions             = ["us-east-2", "eu-central-1"]
  schedule_expression = "rate(1 day)"

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
| `regions` | List of AWS regions to back up SGs and NACLs from | `list(string)` | — |
| `schedule_expression` | EventBridge Scheduler expression (e.g. `rate(1 day)`, `cron(0 2 * * ? *)`) | `string` | `rate(1 day)` |
| `schedule_timezone` | Timezone for the schedule expression (e.g. `UTC`, `Australia/Sydney`) | `string` | `UTC` |
| `schedule_group_name` | EventBridge Scheduler schedule group name | `string` | `default` |
| `lambda_function_name` | Name of the Lambda function | `string` | `save-netpol-to-s3` |
| `lambda_runtime` | Runtime for the Lambda function | `string` | `python3.12` |
| `lambda_timeout` | Timeout in seconds for the Lambda function | `number` | `60` |
| `lambda_memory_size` | Memory size in MB for the Lambda function | `number` | `128` |
| `lambda_architectures` | Instruction set architecture for the Lambda function (`["arm64"]` or `["x86_64"]`) | `list(string)` | `["arm64"]` |
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

## IAM Permissions

The module creates a least-privilege IAM role for the Lambda with:

- `ec2:DescribeSecurityGroups` — read SGs
- `ec2:DescribeNetworkAcls` — read NACLs
- `s3:PutObject` on `{s3_bucket_arn}/*` — write backups to the specified bucket only

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
