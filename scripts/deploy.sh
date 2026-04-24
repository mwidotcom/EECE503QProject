#!/usr/bin/env bash
# Manual deployment helper
# Usage: ./scripts/deploy.sh <env> <image_tag>
# Example: ./scripts/deploy.sh prod prod-abc1234

set -euo pipefail

ENV="${1:-dev}"
IMAGE_TAG="${2:-${ENV}-latest}"
CLUSTER_NAME="shopcloud-${ENV}"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "ERROR: env must be 'dev' or 'prod'" >&2
  exit 1
fi

echo "Deploying tag=${IMAGE_TAG} to env=${ENV} cluster=${CLUSTER_NAME}"

# Update kubeconfig
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# Update image tags in kustomization overlay
OVERLAY_DIR="k8s/overlays/${ENV}"
for svc in catalog cart checkout auth admin; do
  sed -i.bak "s|newTag: .*|newTag: ${IMAGE_TAG}|g" "${OVERLAY_DIR}/kustomization.yaml"
done

# Apply
kubectl apply -k "${OVERLAY_DIR}"

# Wait for rollout
for svc in catalog cart checkout auth admin; do
  echo "Waiting for ${svc} rollout..."
  kubectl rollout status "deployment/${svc}" -n shopcloud --timeout=600s
done

echo "Deployment complete!"
kubectl get pods -n shopcloud
