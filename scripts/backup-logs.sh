#!/usr/bin/env bash
set -euo pipefail
BUCKET="${1:-${BACKUP_BUCKET:-}}"
[[ -n "$BUCKET" ]] || { echo "FAIL: backup bucket not provided"; exit 1; }
AWS_BIN="/usr/local/bin/aws"
STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
[[ -x "$AWS_BIN" ]] || { echo "FAIL: $AWS_BIN not found"; exit 1; }
CONTAINERS=(project2-staging-api project2-production-api terraform-aws-infra-nginx terraform-aws-infra-flask)
COUNT=0
for CONTAINER in "${CONTAINERS[@]}"; do
  OUT="$WORK_DIR/${CONTAINER}-${STAMP}.log.gz"
  if docker logs --since 24h --timestamps "$CONTAINER" 2>&1 | gzip > "$OUT"; then
    COUNT=$((COUNT + 1))
    echo "Compressed logs for $CONTAINER"
  else
    rm -f "$OUT"
    echo "Warning: could not read logs for $CONTAINER"
  fi
done
[[ "$COUNT" -gt 0 ]] || { echo "FAIL: no logs collected"; exit 1; }
"$AWS_BIN" s3 cp "$WORK_DIR/" "s3://${BUCKET}/${STAMP}/" --recursive --sse AES256 --region "${AWS_DEFAULT_REGION:-us-east-1}"
echo "Backup uploaded to s3://${BUCKET}/${STAMP}/ ($COUNT archives)"
