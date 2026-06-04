#!/usr/bin/env bash
# Reliable API tests on minikube without /etc/hosts or minikube tunnel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PF_PORT="${PF_PORT:-8888}"
CLIENT_ID="${CLIENT_ID:-testclient}"
CLIENT_SECRET="${CLIENT_SECRET:-abcdefghgobbledegook1234}"
EMPLOYEE_ID="${EMPLOYEE_ID:-1234567}"

export PATH="/Applications/Docker.app/Contents/Resources/bin:${PATH:-}"

if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo "Enable ingress: minikube addons enable ingress" >&2
  exit 1
fi

kubectl port-forward -n ingress-nginx service/ingress-nginx-controller "${PF_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT
sleep 2

BASE_URL="http://127.0.0.1:${PF_PORT}"
export BASE_URL CLIENT_ID CLIENT_SECRET EMPLOYEE_ID

echo "Testing via ingress port-forward at ${BASE_URL}"
echo ""

"${ROOT}/scripts/test-apis.sh"
