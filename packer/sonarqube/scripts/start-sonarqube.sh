#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

IMDS="http://169.254.169.254"
TOKEN_TTL_SECONDS=21600
MAX_SECRET_ATTEMPTS=12
SECRET_RETRY_SECONDS=10

log() {
  printf 'sonarqube-launcher: %s\n' "$*" >&2
}

classify_secret_error() {
  local error_file="$1"

  if grep -Eqi 'AccessDeniedException|not authorized|AccessDenied' "$error_file"; then
    printf 'authorization'
  elif grep -Eqi 'Could not connect to the endpoint URL|EndpointConnectionError|Connect timeout|Could not resolve|Name or service not known|Temporary failure in name resolution|Network is unreachable|Connection timed out' "$error_file"; then
    printf 'network-or-dns'
  elif grep -Eqi 'ResourceNotFoundException|Secrets Manager can.t find the specified secret' "$error_file"; then
    printf 'secret-not-found'
  elif grep -Eqi 'Unable to locate credentials|NoCredentialsError|InvalidClientTokenId|UnrecognizedClientException|ExpiredToken' "$error_file"; then
    printf 'instance-role-credentials'
  elif grep -Eqi 'ValidationException|InvalidParameter' "$error_file"; then
    printf 'invalid-secret-reference-or-request'
  elif grep -Eqi 'aws: command not found|command not found' "$error_file"; then
    printf 'aws-cli-unavailable'
  else
    printf 'other-aws-cli-error'
  fi
}

IMDS_TOKEN="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --request PUT \
  --header "X-aws-ec2-metadata-token-ttl-seconds: \${TOKEN_TTL_SECONDS}" \
  "\${IMDS}/latest/api/token")"

IMDS_HEADER="X-aws-ec2-metadata-token: \${IMDS_TOKEN}"

get_instance_tag() {
  local tag_name="$1"
  curl --fail --silent --show-error \
    --connect-timeout 2 \
    --max-time 5 \
    --header "\${IMDS_HEADER}" \
    "\${IMDS}/latest/meta-data/tags/instance/\${tag_name}"
}

IDENTITY_DOCUMENT="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --header "\${IMDS_HEADER}" \
  "\${IMDS}/latest/dynamic/instance-identity/document")"

AWS_REGION="$(jq -er '.region' <<<"\${IDENTITY_DOCUMENT}")"
DB_HOST="$(get_instance_tag sonarqube-db-host)"
DB_PORT="$(get_instance_tag sonarqube-db-port)"
DB_NAME="$(get_instance_tag sonarqube-db-name)"
SECRET_ARN="$(get_instance_tag sonarqube-db-secret-arn)"

if [[ ! "\${DB_PORT}" =~ ^[0-9]{1,5}$ ]] || (( DB_PORT < 1 || DB_PORT > 65535 )); then
  log "Database port metadata is invalid."
  exit 1
fi

if [[ -z "\${DB_HOST}" || -z "\${DB_NAME}" || -z "\${SECRET_ARN}" ]]; then
  log "Required database connection metadata is missing."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  log "AWS CLI is not available in the service environment."
  exit 1
fi

AWS_ERROR_FILE="$(mktemp)"
trap 'rm -f "$AWS_ERROR_FILE"' EXIT

SECRET_JSON=""
for ((attempt = 1; attempt <= MAX_SECRET_ATTEMPTS; attempt++)); do
  : >"\${AWS_ERROR_FILE}"

  if SECRET_JSON="$(aws secretsmanager get-secret-value \
      --region "\${AWS_REGION}" \
      --secret-id "\${SECRET_ARN}" \
      --query SecretString \
      --output text 2>"\${AWS_ERROR_FILE}")"; then
    break
  fi

  ERROR_CATEGORY="$(classify_secret_error "\${AWS_ERROR_FILE}")"
  if (( attempt == MAX_SECRET_ATTEMPTS )); then
    log "Secrets Manager request failed after \${MAX_SECRET_ATTEMPTS} attempts (category=\${ERROR_CATEGORY})."
    exit 1
  fi

  log "Secrets Manager request failed (category=\${ERROR_CATEGORY}); retry \${attempt}/\${MAX_SECRET_ATTEMPTS}."
  sleep "\${SECRET_RETRY_SECONDS}"
done

export SONAR_JDBC_URL="jdbc:postgresql://\${DB_HOST}:\${DB_PORT}/\${DB_NAME}"
export SONAR_JDBC_USERNAME="$(jq -er '.username' <<<"\${SECRET_JSON}")"
export SONAR_JDBC_PASSWORD="$(jq -er '.password' <<<"\${SECRET_JSON}")"
unset SECRET_JSON IDENTITY_DOCUMENT IMDS_TOKEN IMDS_HEADER

SONARQUBE_JAR="$(find /opt/sonarqube/lib \
  -maxdepth 1 \
  -type f \
  -name 'sonar-application-*.jar' \
  -print -quit)"

if [[ -z "\${SONARQUBE_JAR}" ]]; then
  log "SonarQube application JAR was not found."
  exit 1
fi

exec /usr/bin/java \
  -Xms32m \
  -Xmx32m \
  -Djava.net.preferIPv4Stack=true \
  -jar "\${SONARQUBE_JAR}"
