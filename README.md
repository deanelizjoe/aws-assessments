# AWS Multi-Region Compute Assessment

A production-grade, multi-region AWS infrastructure using Terraform. Provisions a centralized Cognito auth pool in `us-east-1`, with identical compute stacks deployed to both `us-east-1` and `eu-west-1`.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     us-east-1                           │
│  ┌─────────────────┐                                    │
│  │  Cognito Pool   │ ◄── Single source of truth for JWT │
│  └────────┬────────┘                                    │
│           │ authorizes                                   │
│  ┌────────▼────────────────────────────────────────┐    │
│  │              API Gateway (HTTP API)              │    │
│  │    /greet ──► Lambda Greeter ──► DynamoDB        │    │
│  │                              └─► SNS (verify)    │    │
│  │    /dispatch ► Lambda Dispatcher ──► ECS Fargate │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
         (identical stack mirrored in eu-west-1)
```

## Repository Structure

```
aws-assessment/
├── terraform/
│   ├── modules/
│   │   ├── auth/          # Cognito User Pool (us-east-1 only)
│   │   └── compute/       # API GW + Lambda + DynamoDB + ECS
│   └── envs/
│       ├── us-east-1/     # Region-specific root config
│       └── eu-west-1/
├── lambdas/
│   ├── greeter/           # /greet handler
│   └── dispatcher/        # /dispatch handler
├── ecs/
│   └── entrypoint.sh      # ECS task entrypoint
├── tests/
│   └── integration_test.py
└── .github/workflows/
    └── deploy.yml
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with sufficient permissions
- Python 3.9+ (for test script)
- `pip install boto3 requests pytest`

## Deployment

### 1. Deploy Auth (us-east-1)

```bash
cd terraform/envs/us-east-1
terraform init
terraform apply -target=module.auth
```

Note the `cognito_user_pool_id` and `cognito_client_id` outputs.

### 2. Deploy Compute — both regions

```bash
# us-east-1
cd terraform/envs/us-east-1
terraform apply

# eu-west-1
cd terraform/envs/eu-west-1
terraform init
terraform apply
```

### 3. Run Integration Tests

```bash
export COGNITO_USER_POOL_ID=<from output>
export COGNITO_CLIENT_ID=<from output>
export COGNITO_USERNAME=<your-email>
export COGNITO_PASSWORD=<your-password>
export API_URL_USE1=<us-east-1 API Gateway URL>
export API_URL_EUW1=<eu-west-1 API Gateway URL>

python tests/integration_test.py
```

## Security Controls

- All Lambda functions run with least-privilege IAM roles
- DynamoDB encrypted at rest (AWS-managed key)
- API Gateway endpoints protected by Cognito JWT authorizer
- ECS tasks run in public subnet (no NAT Gateway) with restrictive SG
- State stored in S3 with DynamoDB locking (configure backend per env)
- tfsec and checkov scan on every PR via CI/CD
