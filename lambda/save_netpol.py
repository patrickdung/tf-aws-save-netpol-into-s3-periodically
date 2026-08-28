"""Back up EC2 Security Groups and Network ACLs from one or more AWS regions to S3.

For each region the data is first written to temporary keys inside the run's
timestamp directory and is only promoted to the final file names after BOTH
describe calls have succeeded. Marker objects are used so that only complete,
verified backups are present under their final names:

    {base}/{region}/netpol/{timestamp}/.in-progress        (created first)
    {base}/{region}/netpol/{timestamp}/.tmp.security-groups.json
    {base}/{region}/netpol/{timestamp}/.tmp.network-acls.json
    {base}/{region}/netpol/{timestamp}/security-groups.json   (final, complete)
    {base}/{region}/netpol/{timestamp}/network-acls.json      (final, complete)

On failure for a region the temp/marker objects are removed and a
    {base}/{region}/netpol/{timestamp}/.failed
object containing the error detail is written instead. The handler then
continues with the remaining regions.

The timestamp is ISO 8601 (UTC), e.g. 2026-08-28T143000.
"""

import json
import os
import boto3
from datetime import datetime, timezone

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["S3_BUCKET_NAME"]
# Comma-separated list of regions to back up (e.g. "us-east-2,eu-central-1").
REGIONS = [r.strip() for r in os.environ["REGIONS"].split(",") if r.strip()]
# Optional base folder path between the bucket root and the region directory.
# Leading/trailing slashes are ignored; "" means the bucket root.
BASE_FOLDER = os.environ.get("S3_BASE_FOLDER_PATH", "").strip("/")


def _key_prefix(region, timestamp):
    """Return the S3 key prefix for a region's backup run (no trailing issues)."""
    if BASE_FOLDER:
        return f"{BASE_FOLDER}/{region}/netpol/{timestamp}/"
    return f"{region}/netpol/{timestamp}/"


def _paginate(ec2, operation, result_key):
    """Call a paginated EC2 describe operation and return the full result list."""
    paginator = ec2.get_paginator(operation)
    results = []
    for page in paginator.paginate():
        results.extend(page[result_key])
    return results


def _put_json(key, obj):
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=json.dumps(obj, default=str, indent=2),
        ContentType="application/json",
    )


def _put_text(key, text):
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=text,
        ContentType="text/plain",
    )


def _delete(key):
    s3.delete_object(Bucket=BUCKET_NAME, Key=key)


def _copy(source_key, dest_key):
    s3.copy_object(
        Bucket=BUCKET_NAME,
        Key=dest_key,
        CopySource={"Bucket": BUCKET_NAME, "Key": source_key},
    )


def backup_region(region, timestamp):
    """Back up all Security Groups and Network ACLs in one region to S3.

    Writes to temp keys first and promotes them to final names only after
    both describe calls succeed. Raises on failure (handled by the caller).
    """
    ec2 = boto3.client("ec2", region_name=region)
    prefix = _key_prefix(region, timestamp)

    in_progress_key = f"{prefix}.in-progress"
    tmp_sg_key = f"{prefix}.tmp.security-groups.json"
    tmp_nacl_key = f"{prefix}.tmp.network-acls.json"
    final_sg_key = f"{prefix}security-groups.json"
    final_nacl_key = f"{prefix}network-acls.json"

    # Mark the run as in-progress so temp files are never mistaken for final data.
    _put_text(in_progress_key, f"backup run {timestamp} in progress\n")

    # Fetch the full state via pagination (safe for large accounts).
    security_groups = _paginate(ec2, "describe_security_groups", "SecurityGroups")
    network_acls = _paginate(ec2, "describe_network_acls", "NetworkAcls")

    # Stage the data to temp keys.
    _put_json(tmp_sg_key, security_groups)
    _put_json(tmp_nacl_key, network_acls)

    # Promote to final names only now that both succeeded.
    _copy(tmp_sg_key, final_sg_key)
    _copy(tmp_nacl_key, final_nacl_key)

    # Clean up temp keys and the in-progress marker (keep the final files).
    _delete(tmp_sg_key)
    _delete(tmp_nacl_key)
    _delete(in_progress_key)

    return {
        "region": region,
        "sg_count": len(security_groups),
        "nacl_count": len(network_acls),
        "path": f"s3://{BUCKET_NAME}/{prefix}",
    }


def handle_region_failure(region, timestamp, error):
    """Clean up partial state and write a .failed marker for this region's run."""
    prefix = _key_prefix(region, timestamp)
    for marker in (
        f"{prefix}.in-progress",
        f"{prefix}.tmp.security-groups.json",
        f"{prefix}.tmp.network-acls.json",
    ):
        try:
            _delete(marker)
        except Exception:
            pass  # best-effort cleanup

    _put_json(
        f"{prefix}.failed",
        {
            "region": region,
            "timestamp": timestamp,
            "error": str(error),
        },
    )


def lambda_handler(event, context):
    """Export Security Groups and Network ACLs for each configured region to S3.

    All regions share the same timestamp so they are grouped under one backup
    run. A failure in one region does not stop the others; failed regions are
    reported in the response body and via a .failed marker object in S3.
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%S")

    succeeded = []
    failed = []
    for region in REGIONS:
        try:
            succeeded.append(backup_region(region, timestamp))
        except Exception as exc:  # noqa: BLE001 - report and continue
            handle_region_failure(region, timestamp, exc)
            failed.append({"region": region, "error": str(exc)})

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "timestamp": timestamp,
                "succeeded": succeeded,
                "failed": failed,
            },
            indent=2,
        ),
    }
