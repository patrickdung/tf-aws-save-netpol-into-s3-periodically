import json
import os
import boto3
from datetime import datetime, timezone

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["S3_BUCKET_NAME"]
# Comma-separated list of regions to back up (e.g. "us-east-2,eu-central-1").
REGIONS = [r.strip() for r in os.environ["REGIONS"].split(",") if r.strip()]


def backup_region(region, timestamp):
    """Back up all Security Groups and Network ACLs in a single region to S3.

    S3 key structure:
      {region}/netpol/{timestamp}/security-groups.json
      {region}/netpol/{timestamp}/network-acls.json
    """
    ec2 = boto3.client("ec2", region_name=region)

    # Build the S3 key prefix: {region}/netpol/{timestamp}/
    key_prefix = f"{region}/netpol/{timestamp}/"

    # Fetch current state
    security_groups = ec2.describe_security_groups()["SecurityGroups"]
    network_acls = ec2.describe_network_acls()["NetworkAcls"]

    # Save security groups
    sg_key = f"{key_prefix}security-groups.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=sg_key,
        Body=json.dumps(security_groups, default=str, indent=2),
        ContentType="application/json",
    )

    # Save network ACLs
    nacl_key = f"{key_prefix}network-acls.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=nacl_key,
        Body=json.dumps(network_acls, default=str, indent=2),
        ContentType="application/json",
    )

    return {
        "region": region,
        "sg_count": len(security_groups),
        "nacl_count": len(network_acls),
        "path": f"s3://{BUCKET_NAME}/{key_prefix}",
    }


def lambda_handler(event, context):
    """Export all Security Groups and Network ACLs for each configured region to S3.

    The timestamp is in ISO 8601 extended format, e.g. 2026-08-16THHMMSS (UTC).
    All regions share the same timestamp so they are grouped under one backup run.
    """
    now = datetime.now(timezone.utc)
    timestamp = now.strftime("%Y-%m-%dT%H%M%S")

    results = []
    for region in REGIONS:
        results.append(backup_region(region, timestamp))

    return {
        "statusCode": 200,
        "body": json.dumps(results, indent=2),
    }
