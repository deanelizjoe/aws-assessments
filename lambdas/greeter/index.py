"""
lambdas/greeter/index.py

Triggered by GET /greet.
1. Writes a log record to the regional DynamoDB table.
2. Publishes a verification payload to the Unleash SNS topic.
3. Returns a 200 with the executing region.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Environment variables (injected by Terraform) ───────────────────────────
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
UNLEASH_SNS_ARN = os.environ["UNLEASH_SNS_ARN"]
AWS_REGION_NAME = os.environ["AWS_REGION_NAME"]
REPO_URL = os.environ["REPO_URL"]
AUTHOR_EMAIL = os.environ["AUTHOR_EMAIL"]

# ── AWS clients ──────────────────────────────────────────────────────────────
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION_NAME)
table = dynamodb.Table(DYNAMODB_TABLE)

# SNS client — the Unleash topic lives in us-east-1 regardless of our region
# sns = boto3.client("sns", region_name="us-east-1")
sns = boto3.client("sns", region_name="ap-southeast-2")


def handler(event: dict, context) -> dict:
    """Lambda entry point."""
    request_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    logger.info("Greeter invoked | region=%s | request_id=%s",
                AWS_REGION_NAME, request_id)

    # ── 1. Write to DynamoDB ─────────────────────────────────────────────────
    try:
        table.put_item(
            Item={
                "RequestId": request_id,
                "Timestamp": timestamp,
                "Region": AWS_REGION_NAME,
                "Source": "greeter-lambda",
            }
        )
        logger.info("DynamoDB record written | request_id=%s", request_id)
    except ClientError as exc:
        logger.error("DynamoDB put_item failed: %s", exc)
        return _error(500, "Failed to write DynamoDB record")

    # ── 2. Publish verification payload to Unleash SNS ───────────────────────
    verification_payload = {
        "email": AUTHOR_EMAIL,
        "source": "Lambda",
        "region": AWS_REGION_NAME,
        "repo": REPO_URL,
    }

    try:
        response = sns.publish(
            TopicArn=UNLEASH_SNS_ARN,
            Message=json.dumps(verification_payload),
        )
        logger.info(
            "SNS publish success | message_id=%s | payload=%s",
            response["MessageId"],
            verification_payload,
        )
    except ClientError as exc:
        logger.error("SNS publish failed: %s", exc)
        # Non-fatal — we still return 200 so the test can validate region routing.
        # In production you'd likely want a dead-letter queue here.

    # ── 3. Return 200 ────────────────────────────────────────────────────────
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "Hello from the Greeter!",
                "region": AWS_REGION_NAME,
                "requestId": request_id,
                "timestamp": timestamp,
            }
        ),
    }


def _error(status_code: int, message: str) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }
