#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
terraform_dir="$(cd "${script_dir}/../terraform" && pwd)"

: "${AWS_REGION:=eu-west-1}"
account_id="$(aws sts get-caller-identity --query Account --output text)"
: "${TF_STATE_BUCKET:=starttech-terraform-state-${account_id}}"

if ! aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" 2>/dev/null; then
  aws s3api create-bucket \
    --bucket "${TF_STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  aws s3api put-public-access-block \
    --bucket "${TF_STATE_BUCKET}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-versioning \
    --bucket "${TF_STATE_BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket "${TF_STATE_BUCKET}" \
    --server-side-encryption-configuration \
      'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]'
fi

terraform -chdir="${terraform_dir}" fmt -check -recursive
terraform -chdir="${terraform_dir}" init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=starttech-infra/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
terraform -chdir="${terraform_dir}" validate
terraform -chdir="${terraform_dir}" plan -out=starttech.tfplan
terraform -chdir="${terraform_dir}" apply -auto-approve starttech.tfplan

printf 'Terraform state bucket: %s\n' "${TF_STATE_BUCKET}"
terraform -chdir="${terraform_dir}" output
