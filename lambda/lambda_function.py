import os
import json
import logging
import boto3
from datetime import datetime, timezone, timedelta

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
AGE_DAYS = int(os.getenv("AGE_DAYS", "30"))
WHITELIST_TAGS = json.loads(os.getenv("WHITELIST_TAGS", '["Keep","DoNotDelete"]'))
SNS_ARN = os.getenv("SNS_ARN", "")

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

def publish(subject, message):
    LOG.info("Publishing to SNS")
    if not SNS_ARN:
        LOG.info("SNS_ARN not configured, printing output:\n%s", message)
        return
    try:
        sns.publish(TopicArn=SNS_ARN, Subject=subject, Message=message)
    except Exception as e:
        LOG.exception("SNS publish failed: %s", e)

def is_whitelisted(tags):
    if not tags:
        return False
    for t in tags:
        if t.get("Key") in WHITELIST_TAGS:
            return True
    return False

def find_unattached_volumes(age_days):
    vols = ec2.describe_volumes(Filters=[{"Name":"status","Values":["available"]}])["Volumes"]
    cutoff = datetime.now(timezone.utc) - timedelta(days=age_days)
    candidates = []
    for v in vols:
        created = v.get("CreateTime")
        if created and created < cutoff and not is_whitelisted(v.get("Tags")):
            candidates.append(v)
    return candidates

def delete_volume(volume_id):
    if DRY_RUN:
        LOG.info("DRY RUN delete volume %s", volume_id)
        return {"VolumeId": volume_id, "Deleted": False, "DryRun": True}
    ec2.delete_volume(VolumeId=volume_id)
    return {"VolumeId": volume_id, "Deleted": True}

def lambda_handler(event, context):
    summary = {"deleted": [], "dry_run": DRY_RUN}
    LOG.info("Starting cost optimizer run. DRY_RUN=%s AGE_DAYS=%s", DRY_RUN, AGE_DAYS)

    vols = find_unattached_volumes(AGE_DAYS)
    LOG.info("Found %d unattached volumes", len(vols))
    for v in vols:
        try:
            res = delete_volume(v["VolumeId"])
            summary["deleted"].append(res)
        except Exception as e:
            LOG.exception("Failed to delete volume %s", v.get("VolumeId"))

    message = json.dumps(summary, default=str, indent=2)
    publish("Cost Optimizer Run", message)
    return {"status": "ok", "summary": summary}
