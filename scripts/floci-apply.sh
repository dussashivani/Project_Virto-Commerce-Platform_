#!/usr/bin/env bash
# Provision the emulated infrastructure with OpenTofu/Terraform against Floci, then verify with the AWS CLI.
source "$(dirname "$0")/_lib.sh"
TF="$(command -v tofu || command -v terraform || true)"; [ -n "$TF" ] || { echo "Install OpenTofu or Terraform" >&2; exit 2; }
need aws
export AWS_ENDPOINT_URL=http://localhost:4566 AWS_DEFAULT_REGION=us-east-1 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
cd terraform/envs/floci
"$TF" init -input=false
"$TF" apply -input=false -auto-approve
log "Verify through AWS CLI (emulated)"
BUCKET="$("$TF" output -raw backup_bucket)"
aws s3api head-bucket --bucket "$BUCKET" && ok "bucket $BUCKET"
aws secretsmanager list-secrets --query 'SecretList[].Name'
aws ecs list-clusters
aws logs describe-log-groups --query 'logGroups[].logGroupName'
aws ec2 describe-vpcs --query 'Vpcs[].VpcId' || true
