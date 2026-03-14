#!/usr/bin/env sh
# ecs/entrypoint.sh
#
# NOTE: This script is provided as documentation / alternative approach.
# The primary mechanism uses `amazon/aws-cli` with a direct `command` override
# in the ECS task definition (see terraform/modules/compute/main.tf).
#
# If you prefer a custom image, build from this script and push to ECR.
# The container must exit 0 after publishing so ECS marks the task STOPPED.

set -euo pipefail

UNLEASH_SNS_ARN="${UNLEASH_SNS_ARN:-arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic}"
AUTHOR_EMAIL="${AUTHOR_EMAIL:-your_email@example.com}"
REPO_URL="${REPO_URL:-https://github.com/candidate/aws-assessment}"
# EXECUTING_REGION is injected by the Dispatcher Lambda via container override
EXECUTING_REGION="${EXECUTING_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

PAYLOAD=$(printf '{"email":"%s","source":"ECS","region":"%s","repo":"%s"}' \
  "$AUTHOR_EMAIL" "$EXECUTING_REGION" "$REPO_URL")

echo "Publishing SNS message from ECS task..."
echo "Region  : $EXECUTING_REGION"
echo "Payload : $PAYLOAD"

aws sns publish \
  --region us-east-1 \
  --topic-arn "$UNLEASH_SNS_ARN" \
  --message "$PAYLOAD"

echo "SNS publish successful. Task complete."
exit 0
