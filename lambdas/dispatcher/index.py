"""
lambdas/dispatcher/index.py

Triggered by POST /dispatch.
Calls ECS RunTask to launch a Fargate task that publishes to the Unleash SNS topic.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Environment variables ────────────────────────────────────────────────────
ECS_CLUSTER_ARN = os.environ["ECS_CLUSTER_ARN"]
ECS_TASK_DEF_ARN = os.environ["ECS_TASK_DEF_ARN"]
ECS_SUBNET_ID = os.environ["ECS_SUBNET_ID"]
ECS_SECURITY_GRP_ID = os.environ["ECS_SECURITY_GRP_ID"]
AWS_REGION_NAME = os.environ["AWS_REGION_NAME"]

ecs = boto3.client("ecs", region_name=AWS_REGION_NAME)


def handler(event: dict, context) -> dict:
    """Lambda entry point."""
    logger.info("Dispatcher invoked | region=%s", AWS_REGION_NAME)

    try:
        response = ecs.run_task(
            cluster=ECS_CLUSTER_ARN,
            taskDefinition=ECS_TASK_DEF_ARN,
            launchType="FARGATE",
            networkConfiguration={
                "awsvpcConfiguration": {
                    "subnets": [ECS_SUBNET_ID],
                    "securityGroups": [ECS_SECURITY_GRP_ID],
                    # Public subnet — no NAT Gateway required
                    "assignPublicIp": "ENABLED",
                }
            },
            # Pass the region as an override so the container can embed it in
            # its SNS payload at runtime (the task definition uses a static
            # JSON-encoded message; for dynamic region embedding you'd override
            # the command here).
            overrides={
                "containerOverrides": [
                    {
                        "name": "publisher",
                        "environment": [
                            {"name": "EXECUTING_REGION", "value": AWS_REGION_NAME}
                        ],
                    }
                ]
            },
        )
    except ClientError as exc:
        logger.error("ECS RunTask failed: %s", exc)
        return _error(500, f"ECS RunTask failed: {exc.response['Error']['Message']}")

    failures = response.get("failures", [])
    if failures:
        logger.error("ECS RunTask returned failures: %s", failures)
        return _error(
            500, f"ECS task launch failed: {failures[0].get('reason', 'unknown')}"
        )

    tasks = response.get("tasks", [])
    task_arn = tasks[0]["taskArn"] if tasks else "unknown"
    logger.info(
        "ECS task launched | task_arn=%s | region=%s", task_arn, AWS_REGION_NAME
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "Fargate task dispatched successfully",
                "region": AWS_REGION_NAME,
                "taskArn": task_arn,
            }
        ),
    }


def _error(status_code: int, message: str) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": message}),
    }
