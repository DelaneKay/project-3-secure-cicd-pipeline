#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROFILE="${AWS_PROFILE:-mds-devsecops-lab}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-project-3-tfstate-${ACCOUNT_ID}-${REGION}}"

if [[ "$REGION" != "us-east-1" ]]; then
  echo "This lab bootstrap script is configured for us-east-1." >&2
  exit 1
fi

if ! aws s3api head-bucket --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET" --object-ownership BucketOwnerEnforced --profile "$PROFILE" --region "$REGION"
fi

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"
aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
  --ownership-controls Rules='[{ObjectOwnership=BucketOwnerEnforced}]' \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"

policy="$(mktemp)"
trap 'rm -f "$policy"' EXIT
cat > "$policy" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::$BUCKET", "arn:aws:s3:::$BUCKET/*"],
    "Condition": {"Bool": {"aws:SecureTransport": "false"}}
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$policy" \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=Project,Value=project-3-secure-cicd-pipeline},{Key=Purpose,Value=terraform-state}]' \
  --expected-bucket-owner "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION"

printf 'Terraform state bucket ready: %s (%s)\n' "$BUCKET" "$REGION"
