# StartTech Infrastructure

Terraform infrastructure for the StartTech full-stack assessment. It provisions a two-AZ VPC, Amazon EKS, Amazon ElastiCache for Redis, a private S3 frontend bucket, Amazon ECR, a public backend ALB, and one CloudFront distribution that securely serves both the SPA and `/api/*` requests.

## Architecture

- `10.0.0.0/16` VPC with two public, two EKS-private, and two database-private subnets.
- Two NAT gateways keep worker nodes and Redis off the public internet while preserving outbound availability.
- `starttech-cluster` runs EKS 1.34 with the `starttech-node-group` managed node group and two `t3.medium` nodes.
- The backend ALB forwards to Kubernetes NodePort `30080`, which maps to container port `8080`.
- The private frontend bucket is accessed only through CloudFront OAC.
- `S3-Frontend` is the default CloudFront origin; `ALB-Backend` handles `/api/*` with caching disabled.
- CloudFront rewrites S3 403 and 404 responses to `/index.html` with status 200 for SPA routing.
- GitHub Actions uses repository-scoped OIDC roles rather than long-lived AWS keys.

## Layout

```text
terraform/
  main.tf
  variables.tf
  outputs.tf
  terraform.tfvars.example
  modules/{networking,eks,storage,cdn,database}/
scripts/deploy-infrastructure.sh
.github/workflows/infrastructure-deploy.yml
```

## Initial deployment

The first deployment is local because it creates the GitHub OIDC roles used by later CI runs. It also creates a versioned, encrypted S3 state bucket outside the main stack so `terraform destroy` cannot accidentally remove its own state.

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
export AWS_REGION=eu-west-1
./scripts/deploy-infrastructure.sh
```

After apply, configure these GitHub repository variables:

| Repository | Variable | Terraform source |
| --- | --- | --- |
| `starttech-infra` | `AWS_REGION` | `eu-west-1` |
| `starttech-infra` | `AWS_INFRASTRUCTURE_ROLE_ARN` | `infrastructure_github_role_arn` |
| `starttech-infra` | `TF_STATE_BUCKET` | Printed by the deployment script |
| `starttech-application` | `AWS_REGION` | `eu-west-1` |
| `starttech-application` | `AWS_APPLICATION_ROLE_ARN` | `application_github_role_arn` |
| `starttech-application` | `FRONTEND_BUCKET` | `frontend_bucket_name` |
| `starttech-application` | `CLOUDFRONT_DISTRIBUTION_ID` | `cloudfront_distribution_id` |
| `starttech-application` | `CLOUDFRONT_DOMAIN` | `cloudfront_domain_name` |

The application repository additionally needs `MONGO_URI` and `JWT_SECRET_KEY` GitHub Actions secrets.

## Validation

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

## Grader access

Terraform creates the `start-tech-grader` IAM user and attaches exactly the requested read-only policy. Access keys and console passwords are intentionally not stored in Terraform state. Create those credentials immediately before submission and deliver them only through the requested private Google Doc.

## Cost warning

EKS, two `t3.medium` nodes, two NAT gateways, an ALB, and ElastiCache incur hourly charges. Destroy the assessment stack when grading is complete:

```bash
terraform -chdir=terraform destroy
```
