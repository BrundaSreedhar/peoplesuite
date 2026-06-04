#!/usr/bin/env bash
# Build images inside minikube's Docker daemon so imagePullPolicy: IfNotPresent works.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v minikube >/dev/null 2>&1; then
  echo "minikube is not installed or not on PATH" >&2
  exit 1
fi

if ! minikube status >/dev/null 2>&1; then
  echo "Start minikube first: minikube start" >&2
  exit 1
fi

eval "$(minikube docker-env)"

echo "Building peoplesuite-authorization:latest ..."
docker build -t peoplesuite-authorization:latest "${ROOT}/services/authorization"

echo "Building peoplesuite-employee:latest ..."
docker build -t peoplesuite-employee:latest "${ROOT}/services/employee"

echo ""
echo "Done. Restart deployments:"
echo "  kubectl rollout restart deployment -n peoplesuite authorization-service employee-service"
echo "  kubectl get pods -n peoplesuite -w"
