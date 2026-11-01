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

imds_token="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --request PUT \
  --header "X-aws-ec2-metadata-token-ttl-seconds: ${TOKEN_TTL_SECONDS}" \
  "${IMDS}/latest/api/token")"

imds_header="X-aws-ec2-metadata-token: ${imds_token}"

get_instance_tag() {
  local tag_name="$1"
  curl --fail --silent --show-error \
    --connect-timeout 2 \
    --max-time 5 \
    --header "${imds_header}" \
    "${IMDS}/latest/meta-data/tags/instance/${tag_name}"
}

identity_document="$(curl --fail --silent --show-error \
  --connect-timeout 2 \
  --max-time 5 \
  --header "${imds_header}" \
  "${IMDS}/latest/dynamic/instance-identity/document")"

aws_region="$(jq -er '.region' <<<"${identity_document}")"
db_host="$(get_instance_tag sonarqube-db-host)"
db_port="$(get_instance_tag sonarqube-db-port)"
db_name="$(get_instance_tag sonarqube-db-name)"
secret_arn="$(get_instance_tag sonarqube-db-secret-arn)"

if [[ ! "${db_port}" =~ ^[0-9]{1,5}$ ]] || (( db_port < 1 || db_port > 65535 )); then
  log "Database port metadata is invalid."
  exit 1
fi

secret_json=""
for ((attempt = 1; attempt <= MAX_SECRET_ATTEMPTS; attempt++)); do
  if secret_json="$(aws secretsmanager get-secret-value \
      --region "${aws_region}" \
      --secret-id "${secret_arn}" \
      --query SecretString \
      --output text 2>/dev/null)"; then
    break
  fi
  if (( attempt == MAX_SECRET_ATTEMPTS )); then
    log "Could not retrieve the database credentials from Secrets Manager."
    exit 1
  fi
  log "Secrets Manager is not ready; retry ${attempt}/${MAX_SECRET_ATTEMPTS}."
  sleep "${SECRET_RETRY_SECONDS}"
done

export SONAR_JDBC_URL="jdbc:postgresql://${db_host}:${db_port}/${db_name}"
export SONAR_JDBC_USERNAME="$(jq -er '.username' <<<"${secret_json}")"
export SONAR_JDBC_PASSWORD="$(jq -er '.password' <<<"${secret_json}")"
unset secret_json identity_document imds_token imds_header

sonarqube_jar="$(find /opt/sonarqube/lib \
  -maxdepth 1 \
  -type f \
  -name 'sonar-application-*.jar' \
  -print -quit)"

if [[ -z "${sonarqube_jar}" ]]; then
  log "SonarQube application JAR was not found."
  exit 1
fi

exec /usr/bin/java \
  -Xms32m \
  -Xmx32m \
  -Djava.net.preferIPv4Stack=true \
  -jar "${sonarqube_jar}"
