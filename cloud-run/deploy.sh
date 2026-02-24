#!/bin/bash
# ============================================================================
# n8n Cloud Run - Deploy / Update
# ============================================================================
# Deploys n8n to Cloud Run with:
#   - Direct VPC egress (connects to Cloud SQL private IP)
#   - Secrets from Secret Manager
#   - Cloud SQL Auth Proxy sidecar
#
# Run setup.sh first if this is the initial deployment.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

N8N_IMAGE="europe-west1-docker.pkg.dev/${PROJECT_ID}/ai-receptionist/n8n:latest"

echo "============================================"
echo "n8n Cloud Run - Deploy"
echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo "Service: ${SERVICE_NAME}"
echo "Image:   ${N8N_IMAGE}"
echo "============================================"

# --------------------------------------------------------------------------
# Pull and push latest n8n image to Artifact Registry
# --------------------------------------------------------------------------
echo ""
echo "Pulling latest n8n image (linux/amd64) and pushing to Artifact Registry..."
docker pull --platform linux/amd64 docker.n8n.io/n8nio/n8n:latest
docker tag docker.n8n.io/n8nio/n8n:latest "${N8N_IMAGE}"
docker push "${N8N_IMAGE}"

# --------------------------------------------------------------------------
# Deploy to Cloud Run
# --------------------------------------------------------------------------
echo ""
echo "Deploying n8n to Cloud Run..."

gcloud run deploy "${SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --image="${N8N_IMAGE}" \
  --platform=managed \
  --service-account="${SERVICE_ACCOUNT_EMAIL}" \
  --port=5678 \
  --cpu=2 \
  --memory=2Gi \
  --min-instances=1 \
  --max-instances=3 \
  --timeout=3600 \
  --no-cpu-throttling \
  --session-affinity \
  --network="${VPC_NETWORK}" \
  --subnet="${VPC_SUBNET}" \
  --vpc-egress=private-ranges-only \
  --add-cloudsql-instances="${SQL_CONNECTION_NAME}" \
  --set-env-vars=" \
DB_TYPE=postgresdb,\
DB_POSTGRESDB_HOST=${SQL_PRIVATE_IP},\
DB_POSTGRESDB_PORT=${N8N_DB_PORT},\
DB_POSTGRESDB_DATABASE=${N8N_DB_NAME},\
DB_POSTGRESDB_USER=${N8N_DB_USER},\
GENERIC_TIMEZONE=${N8N_TIMEZONE},\
TZ=${N8N_TIMEZONE},\
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=false,\
N8N_RUNNERS_ENABLED=true,\
N8N_DIAGNOSTICS_ENABLED=false,\
N8N_SECURE_COOKIE=true,\
NODE_ENV=production\
" \
  --set-secrets="\
DB_POSTGRESDB_PASSWORD=${SECRET_N8N_DB_PASSWORD}:latest,\
N8N_ENCRYPTION_KEY=${SECRET_N8N_ENCRYPTION_KEY}:latest\
" \
  --allow-unauthenticated

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"

# Get the service URL
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(status.url)")

echo ""
echo "n8n is available at: ${SERVICE_URL}"
echo ""
echo "Optional next steps:"
echo "  1. Map a custom domain:"
echo "     gcloud run domain-mappings create --service=${SERVICE_NAME} \\"
echo "       --domain=n8n.ai-dev.telavox.com --region=${REGION} --project=${PROJECT_ID}"
echo ""
echo "  2. View logs:"
echo "     gcloud run services logs read ${SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID}"
