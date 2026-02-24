#!/bin/bash
# ============================================================================
# n8n Cloud Run - One-Time Setup
# ============================================================================
# Run this ONCE before deploying. It creates:
#   1. Service account for n8n
#   2. Secrets in Secret Manager (DB password + encryption key)
#   3. Database and user on existing Cloud SQL instance
#
# Prerequisites:
#   - gcloud CLI authenticated with owner/editor access
#   - Cloud SQL Auth Proxy running locally (for DB setup)
#     cloud-sql-proxy gtm-labs-484110:europe-west1:ai-receptionist-db-dev
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "============================================"
echo "n8n Cloud Run - Setup"
echo "Project: ${PROJECT_ID}"
echo "Region:  ${REGION}"
echo "============================================"

# --------------------------------------------------------------------------
# 1. Create Service Account
# --------------------------------------------------------------------------
echo ""
echo "[1/4] Creating service account: ${SERVICE_ACCOUNT_NAME}..."

if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}" &>/dev/null; then
  echo "  Service account already exists, skipping."
else
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="n8n Application" \
    --description="Service account for n8n Cloud Run deployment"
  echo "  Created."
fi

# Grant roles
echo "  Granting IAM roles..."
for ROLE in \
  "roles/cloudsql.client" \
  "roles/secretmanager.secretAccessor" \
  "roles/logging.logWriter" \
  "roles/monitoring.metricWriter"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet &>/dev/null
  echo "    ${ROLE}"
done

# --------------------------------------------------------------------------
# 2. Generate and store secrets
# --------------------------------------------------------------------------
echo ""
echo "[2/4] Setting up secrets..."

# Generate random passwords
N8N_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)

# DB Password
if gcloud secrets describe "${SECRET_N8N_DB_PASSWORD}" \
    --project="${PROJECT_ID}" &>/dev/null; then
  echo "  Secret '${SECRET_N8N_DB_PASSWORD}' already exists."
  echo "  To rotate, add a new version manually."
else
  echo -n "${N8N_DB_PASSWORD}" | gcloud secrets create "${SECRET_N8N_DB_PASSWORD}" \
    --project="${PROJECT_ID}" \
    --replication-policy="user-managed" \
    --locations="${REGION}" \
    --data-file=-
  echo "  Created secret: ${SECRET_N8N_DB_PASSWORD}"
fi

# Encryption Key
if gcloud secrets describe "${SECRET_N8N_ENCRYPTION_KEY}" \
    --project="${PROJECT_ID}" &>/dev/null; then
  echo "  Secret '${SECRET_N8N_ENCRYPTION_KEY}' already exists."
else
  echo -n "${N8N_ENCRYPTION_KEY}" | gcloud secrets create "${SECRET_N8N_ENCRYPTION_KEY}" \
    --project="${PROJECT_ID}" \
    --replication-policy="user-managed" \
    --locations="${REGION}" \
    --data-file=-
  echo "  Created secret: ${SECRET_N8N_ENCRYPTION_KEY}"
fi

# --------------------------------------------------------------------------
# 3. Create database and user on Cloud SQL
# --------------------------------------------------------------------------
echo ""
echo "[3/4] Setting up database on Cloud SQL..."
echo "  Instance: ${SQL_INSTANCE}"
echo ""
echo "  NOTE: This step requires Cloud SQL Auth Proxy running locally."
echo "  In a separate terminal, run:"
echo "    cloud-sql-proxy ${SQL_CONNECTION_NAME}"
echo ""
read -p "  Is the Cloud SQL Auth Proxy running? (y/n): " PROXY_READY

if [[ "${PROXY_READY}" != "y" ]]; then
  echo "  Skipping DB setup. Run this script again after starting the proxy."
  echo "  Or create the DB manually with these SQL commands:"
  echo ""
  echo "    CREATE DATABASE ${N8N_DB_NAME};"
  echo "    CREATE USER ${N8N_DB_USER} WITH PASSWORD '<from Secret Manager>';"
  echo "    GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};"
  echo "    \\c ${N8N_DB_NAME}"
  echo "    GRANT CREATE ON SCHEMA public TO ${N8N_DB_USER};"
  echo ""
else
  # Retrieve the DB password from Secret Manager
  DB_PASS=$(gcloud secrets versions access latest \
    --secret="${SECRET_N8N_DB_PASSWORD}" \
    --project="${PROJECT_ID}")

  echo "  Creating database and user..."
  PGPASSWORD=$(gcloud secrets versions access latest \
    --secret="db-password" \
    --project="${PROJECT_ID}") \
  psql -h 127.0.0.1 -p 5432 -U postgres -d postgres <<-EOSQL
    -- Create database if not exists
    SELECT 'CREATE DATABASE ${N8N_DB_NAME}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${N8N_DB_NAME}')\gexec

    -- Create user if not exists
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${N8N_DB_USER}') THEN
        CREATE USER ${N8N_DB_USER} WITH PASSWORD '${DB_PASS}';
      END IF;
    END
    \$\$;

    -- Grant privileges
    GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};
EOSQL

  # Connect to n8n database to grant schema permissions
  PGPASSWORD=$(gcloud secrets versions access latest \
    --secret="db-password" \
    --project="${PROJECT_ID}") \
  psql -h 127.0.0.1 -p 5432 -U postgres -d "${N8N_DB_NAME}" <<-EOSQL
    GRANT CREATE ON SCHEMA public TO ${N8N_DB_USER};
EOSQL

  echo "  Database and user created successfully."
fi

# --------------------------------------------------------------------------
# 4. Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================"
echo "[4/4] Setup Complete!"
echo "============================================"
echo ""
echo "Service Account: ${SERVICE_ACCOUNT_EMAIL}"
echo "Secrets:"
echo "  - ${SECRET_N8N_DB_PASSWORD}"
echo "  - ${SECRET_N8N_ENCRYPTION_KEY}"
echo "Database: ${N8N_DB_NAME} on ${SQL_INSTANCE}"
echo "DB User:  ${N8N_DB_USER}"
echo ""
echo "Next step: Run ./deploy.sh to deploy n8n to Cloud Run"
