#!/bin/bash
# ============================================================================
# n8n Cloud Run - Environment Variables
# ============================================================================
# Source this file before running setup.sh or deploy.sh
# Adjust values as needed for your environment.

# GCP Project
export PROJECT_ID="gtm-labs-484110"
export REGION="europe-west1"

# Cloud SQL (existing instance)
export SQL_INSTANCE="ai-receptionist-db-dev"
export SQL_CONNECTION_NAME="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"
export SQL_PRIVATE_IP="10.83.0.3"

# n8n Database (will be created on existing Cloud SQL instance)
export N8N_DB_NAME="n8n"
export N8N_DB_USER="n8n_app"
export N8N_DB_PORT="5432"

# Networking (existing VPC)
export VPC_NETWORK="ai-receptionist-vpc"
export VPC_SUBNET="ai-receptionist-subnet"

# Cloud Run
export SERVICE_NAME="n8n"
export SERVICE_ACCOUNT_NAME="n8n-app"
export SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Secret Manager
export SECRET_N8N_DB_PASSWORD="n8n-db-password"
export SECRET_N8N_ENCRYPTION_KEY="n8n-encryption-key"
export SECRET_N8N_SMTP_PASS="n8n-smtp-password"

# SMTP (for invitation emails)
export N8N_SMTP_HOST="smtp.gmail.com"
export N8N_SMTP_PORT="587"
export N8N_SMTP_USER="besarion.turmanauli@telavox.com"
export N8N_SMTP_SENDER="besarion.turmanauli@telavox.com"

# Timezone
export N8N_TIMEZONE="Europe/Stockholm"
