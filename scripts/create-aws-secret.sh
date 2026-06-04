#!/usr/bin/env bash
# Create/update Kubernetes AWS credentials from .env
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT}/.env}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Create ${ENV_FILE} from .env.example with real AWS keys." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set in ${ENV_FILE}" >&2
  exit 1
fi

kubectl create secret generic aws-credentials \
  --namespace peoplesuite \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment -n peoplesuite authorization-service employee-service
echo "Applied aws-credentials and restarted deployments."
