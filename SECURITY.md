# Security Notes

## Accepted Risk Exceptions

The following security findings are accepted for this assessment environment
and documented below. Each would be remediated before production deployment.

| Check | Tool | Rationale | Production Fix |
|---|---|---|---|
| `CKV_AWS_115` | checkov | Lambda reserved concurrency not set — ephemeral assessment stack | Set `reserved_concurrent_executions` per traffic model |
| `CKV_AWS_116` | checkov | No Lambda DLQ — SNS failure handled gracefully in code | Add SQS DLQ + CloudWatch alarm |
| `CKV_AWS_117` | checkov | Lambdas not inside VPC — would require NAT Gateway (cost) | VPC endpoints for SNS/DynamoDB; Lambdas in private subnet |
| `CKV2_AWS_29` | checkov | API GW access log — CloudWatch group is provisioned; false-positive on HTTP API v2 $default stage | Verify with `aws apigatewayv2 get-stage` |

## What IS implemented

- ✅ DynamoDB encrypted at rest (SSE with AWS-managed key)
- ✅ DynamoDB point-in-time recovery enabled
- ✅ All IAM roles follow least-privilege (scoped to specific table ARN, log group ARN)
- ✅ ECS task security group: egress HTTPS only, no ingress
- ✅ Cognito: minimum 12-character password, complexity requirements
- ✅ API Gateway: all routes require valid Cognito JWT (no unauthenticated paths)
- ✅ CloudWatch log retention set to 14 days (not unlimited)
- ✅ Cognito deletion protection enabled
- ✅ OIDC-based AWS authentication in CI/CD (no long-lived IAM access keys)
- ✅ tfsec and checkov scans on every PR; SARIF results uploaded to GitHub Security tab
