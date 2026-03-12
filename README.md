# Unleash live AWS DevOps Engineer Assessment

This repository contains a Terraform-based solution for the Unleash live assessment:

- Centralized **Amazon Cognito User Pool** in **us-east-1**
- Identical regional compute stacks in **two AWS regions**
- Protected **HTTP API** routes: `/greet` and `/dispatch`
- Regional **DynamoDB** logging
- **Lambda Greeter** that writes to DynamoDB and publishes to the Unleash verification SNS topic
- **Lambda Dispatcher** that launches a one-shot **ECS Fargate** task
- Fargate task that publishes directly to the Unleash verification SNS topic and exits
- A **Python test script** that authenticates with Cognito, calls both regional APIs concurrently, and prints region/latency assertions
- A **GitHub Actions** workflow for fmt/validate/security scan/plan and a post-deploy test placeholder

## Structure

```text
.
├── .github/workflows/deploy.yml
├── lambdas/
│   ├── dispatcher/app.py
│   └── greeter/app.py
├── modules/
│   ├── cognito/
│   └── regional_stack/
├── scripts/test_deployment.py
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars.example
```

## Multi-region design

The root module defines **two AWS providers**:

- `aws.use1` -> `us-east-1`
- `aws.euw1` -> `eu-west-1`

The solution is split into:

1. `modules/cognito`
   - Runs only in `us-east-1`
   - Creates the Cognito User Pool, User Pool Client, and candidate test user
   - Uses `admin-set-user-password` through `local-exec` to make the supplied password permanent

2. `modules/regional_stack`
   - Instantiated twice, once per region
   - Creates the VPC/public subnets, ECS cluster/task definition, DynamoDB table, two Lambda functions, API Gateway HTTP API, and JWT authorizer
   - Both stacks trust the **same Cognito issuer and client audience from us-east-1**

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured against your sandbox account
- Python 3.10+
- An AWS IAM principal with permissions for Cognito, Lambda, IAM, API Gateway v2, DynamoDB, ECS, EC2 networking, CloudWatch Logs, and SNS publish to the provided topic

## Configure

Copy the sample vars file and edit it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set:

- `candidate_email` = your real recruiting email address
- `repo_url` = your public GitHub repo URL
- `cognito_test_password` = your chosen permanent Cognito password

## Deploy manually

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

After apply, capture these outputs:

```bash
terraform output
```

Important outputs:

- `cognito_user_pool_client_id`
- `region_1_api_base_url`
- `region_2_api_base_url`
- `region_1_name`
- `region_2_name`

## Run the automated test script

Install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run the test:

```bash
python scripts/test_deployment.py \
  --auth-region us-east-1 \
  --user-pool-client-id <cognito_client_id> \
  --username <your_email> \
  --password '<your_password>' \
  --region1-name us-east-1 \
  --region1-base-url <region1_api_base_url> \
  --region2-name eu-west-1 \
  --region2-base-url <region2_api_base_url>
```

What the script does:

1. Calls Cognito `InitiateAuth` in `us-east-1` using `USER_PASSWORD_AUTH`
2. Gets a JWT token
3. Calls `/greet` in both regions concurrently
4. Calls `/dispatch` in both regions concurrently
5. Prints each response, verifies the returned `region`, and prints the latency in milliseconds

## Cost choices

To keep cost low:

- ECS runs as an **on-demand one-shot Fargate task** only when `/dispatch` is invoked
- The task runs in **public subnets with assignPublicIp enabled** so no NAT Gateway is required
- DynamoDB uses **PAY_PER_REQUEST**
- CloudWatch log retention is set to **7 days**

## CI/CD pipeline

The GitHub Actions file includes:

- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `tfsec` security scan
- `terraform plan`
- A clear placeholder showing where the automated test script would run after deployment

## Tear down

Destroy the stack immediately after successful verification:

```bash
terraform destroy
```

## Notes

- The Cognito user is created by Terraform and then upgraded to a **permanent password** with the AWS CLI command `admin-set-user-password`.
- The API is implemented as **API Gateway HTTP API** with a **JWT authorizer** that trusts the Cognito issuer URL from `us-east-1` and the shared app client audience.
- The `/dispatch` endpoint returns once `RunTask` is accepted; the Fargate task then publishes its SNS message asynchronously and exits.
