#!/usr/bin/env bash
# Manual rollback — undoes the last deployment for all services
# Usage: ./scripts/rollback.sh <env>

set -euo pipefail

ENV="${1:-prod}"
CLUSTER_NAME="shopcloud-${ENV}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "ROLLBACK: reverting all services in env=${ENV}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

for svc in catalog cart checkout auth admin; do
  echo "Rolling back ${svc}..."
  kubectl rollout undo "deployment/${svc}" -n shopcloud
done

for svc in catalog cart checkout auth admin; do
  kubectl rollout status "deployment/${svc}" -n shopcloud --timeout=300s
done

echo "Rollback complete."
kubectl get pods -n shopcloud
