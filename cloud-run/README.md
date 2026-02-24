# n8n on Google Cloud Run

Self-hosted n8n workflow automation on Google Cloud Run, connected to an existing
Cloud SQL PostgreSQL instance via private VPC networking.

- **Live URL**: https://n8n-824433763918.europe-west1.run.app
- **Project**: `gtm-labs-484110`
- **Region**: `europe-west1`
- **Status**: Deployed and serving

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Google Cloud — gtm-labs-484110                       │
│                            Region: europe-west1                             │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    VPC: ai-receptionist-vpc                           │  │
│  │                    Subnet: 10.0.0.0/20                                │  │
│  │                                                                       │  │
│  │  ┌─────────────────────┐          ┌─────────────────────────────┐     │  │
│  │  │   Cloud SQL         │          │   Cloud Run                 │     │  │
│  │  │   (Private IP)      │◄─────────│   Service: n8n              │     │  │
│  │  │                     │  Direct  │                             │     │  │
│  │  │   Instance:         │   VPC    │   Image: n8n:latest         │     │  │  
│  │  │   ai-receptionist-  │  Egress  │   (Artifact Registry)       │     │  │
│  │  │   db-dev            │          │                             │     │  │
│  │  │   Postgres 15       │          │   CPU: 2  |  RAM: 2Gi       │     │  │
│  │  │   IP: 10.83.0.3     │          │   Min: 1  |  Max: 3         │     │  │
│  │  │                     │          │   Port: 5678                │     │  │
│  │  │   DB: n8n           │          │                             │     │  │
│  │  │   User: n8n_app     │          │   SA: n8n-app@...           │     │  │
│  │  └─────────────────────┘          └────────────────┬────────────┘     │  │
│  │                                                    │                  │  │
│  └────────────────────────────────────────────────────┼──────────────────┘  │
│                                                       │                     │
│  ┌────────────────────┐   ┌───────────────────────┐   │                     │
│  │  Secret Manager    │   │  Artifact Registry    │   │                     │
│  │                    │   │                       │   │                     │
│  │  n8n-db-password   │   │  ai-receptionist/     │   │                     │
│  │ n8n-encryption-key │   │  n8n:latest           │   │                     │
│  └────────────────────┘   └───────────────────────┘   │                     │
│                                                       │                     │
└───────────────────────────────────────────────────────┼─────────────────────┘
                                                        │
                                                   HTTPS (443)
                                                   Auto TLS by
                                                   Cloud Run
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │   End Users     │
                                              │   Browser / API │
                                              └─────────────────┘
```

## Request Flow

```
User Request
    │
    ▼
https://n8n-824433763918.europe-west1.run.app
    │
    ▼
┌──────────────┐     ┌──────────────────┐     ┌──────────────────────┐
│  Google      │────▶│  Cloud Run       │────▶│  Cloud SQL           │
│  Front End   │     │  n8n container   │     │  PostgreSQL 15       │
│  (TLS)       │◀────│  :5678           │◀────│  10.83.0.3:5432      │
└──────────────┘     └──────────────────┘     └──────────────────────┘
                            │
                            ▼
                     ┌──────────────────┐
                     │  Secret Manager  │
                     │  DB password     │
                     │  Encryption key  │
                     └──────────────────┘
```

## Networking Detail

```
Internet ──HTTPS──▶ Cloud Run (managed ingress, auto TLS)
                         │
                         │  Direct VPC Egress
                         │  (private-ranges-only)
                         │
                         ▼
                    ai-receptionist-vpc
                    ┌──────────────────────────────────┐
                    │  Subnet: ai-receptionist-subnet  │
                    │  CIDR: 10.0.0.0/20               │
                    │                                  │
                    │  Cloud SQL private IP: 10.83.0.3 │
                    │  (VPC Peering via                │
                    │ servicenetworking.googleapis.com)│
                    └──────────────────────────────────┘

No public IP on Cloud SQL.
No VPC connector needed — uses Cloud Run Direct VPC Egress.
```

---

## Deployed Resources

| Resource | Name | Details |
|----------|------|---------|
| **Cloud Run Service** | `n8n` | 2 CPU, 2Gi RAM, min 1 / max 3 instances |
| **Artifact Registry Image** | `europe-west1-docker.pkg.dev/gtm-labs-484110/ai-receptionist/n8n:latest` | Mirrored from `docker.n8n.io/n8nio/n8n` (linux/amd64) |
| **Cloud SQL Database** | `n8n` on `ai-receptionist-db-dev` | PostgreSQL 15, private IP `10.83.0.3` |
| **Cloud SQL User** | `n8n_app` | Password in Secret Manager |
| **Service Account** | `n8n-app@gtm-labs-484110.iam.gserviceaccount.com` | Roles: `cloudsql.client`, `secretmanager.secretAccessor`, `logging.logWriter`, `monitoring.metricWriter` |
| **Secret** | `n8n-db-password` | PostgreSQL password for `n8n_app` |
| **Secret** | `n8n-encryption-key` | n8n encryption key for credential storage |

### Environment Variables (set on Cloud Run)

| Variable | Value |
|----------|-------|
| `DB_TYPE` | `postgresdb` |
| `DB_POSTGRESDB_HOST` | `10.83.0.3` |
| `DB_POSTGRESDB_PORT` | `5432` |
| `DB_POSTGRESDB_DATABASE` | `n8n` |
| `DB_POSTGRESDB_USER` | `n8n_app` |
| `DB_POSTGRESDB_PASSWORD` | *(from Secret Manager)* |
| `N8N_ENCRYPTION_KEY` | *(from Secret Manager)* |
| `GENERIC_TIMEZONE` | `Asia/Tbilisi` |
| `TZ` | `Asia/Tbilisi` |
| `N8N_RUNNERS_ENABLED` | `true` |
| `N8N_SECURE_COOKIE` | `true` |
| `NODE_ENV` | `production` |

---

## Prerequisites

- **gcloud CLI** authenticated with project owner/editor access
- **Docker Desktop** running locally (for pulling/pushing the n8n image)
- **Artifact Registry auth** configured:
  ```bash
  gcloud auth configure-docker europe-west1-docker.pkg.dev
  ```

---

## Deployment Steps

### 1. Review configuration

Edit `env.sh` to verify all values match your environment (project, region, VPC, etc.).

### 2. Run one-time setup

Creates the service account, IAM roles, secrets, database, and DB user:

```bash
chmod +x setup.sh deploy.sh env.sh
./setup.sh
```

The database and user are created via `gcloud sql` commands (no proxy needed):

```bash
gcloud sql databases create n8n --instance=ai-receptionist-db-dev --project=gtm-labs-484110
gcloud sql users create n8n_app --instance=ai-receptionist-db-dev --project=gtm-labs-484110 --password="<from Secret Manager>"
```

### 3. Deploy to Cloud Run

```bash
./deploy.sh
```

The deploy script:
1. Pulls the latest `docker.n8n.io/n8nio/n8n` image (linux/amd64)
2. Tags and pushes it to Artifact Registry
3. Deploys the Cloud Run service with all env vars and secrets

### 4. (Optional) Map a custom domain

```bash
gcloud run domain-mappings create \
  --service=n8n \
  --domain=n8n.ai-dev.telavox.com \
  --region=europe-west1 \
  --project=gtm-labs-484110
```

Then add a CNAME record in your DNS provider pointing `n8n.ai-dev.telavox.com` to `ghs.googlehosted.com`.

---

## Updating n8n

To deploy the latest n8n version, just re-run:

```bash
./deploy.sh
```

This pulls the latest image, pushes to Artifact Registry, and updates the Cloud Run service with zero downtime.

---

## Useful Commands

```bash
# View logs
gcloud run services logs read n8n --region=europe-west1 --project=gtm-labs-484110

# View service details
gcloud run services describe n8n --region=europe-west1 --project=gtm-labs-484110

# Scale to zero (pause — saves cost, cold start on next request)
gcloud run services update n8n --min-instances=0 \
  --region=europe-west1 --project=gtm-labs-484110

# Scale back up (always-on)
gcloud run services update n8n --min-instances=1 \
  --region=europe-west1 --project=gtm-labs-484110

# Delete the Cloud Run service
gcloud run services delete n8n --region=europe-west1 --project=gtm-labs-484110

# Access a secret value
gcloud secrets versions access latest --secret=n8n-db-password --project=gtm-labs-484110

# Check Cloud SQL databases
gcloud sql databases list --instance=ai-receptionist-db-dev --project=gtm-labs-484110
```

---

## File Structure

```
cloud-run/
├── README.md      ← This file
├── env.sh         ← Environment variables (project, region, VPC, DB, etc.)
├── setup.sh       ← One-time setup (service account, secrets, database)
└── deploy.sh      ← Deploy/update n8n on Cloud Run
```

---

## Cost Estimate

| Resource | Monthly Cost | Notes |
|----------|-------------|-------|
| **Cloud Run** | ~$15–30 | 1 min instance, 2 CPU, 2Gi RAM |
| **Cloud SQL** | $0 extra | Shared existing `ai-receptionist-db-dev` instance |
| **Artifact Registry** | ~$0.10 | ~500MB stored image |
| **Secret Manager** | ~$0.06 | 2 secrets, minimal access |
| **Total** | **~$15–30/month** | |

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `exec format error` in logs | ARM image pushed from Apple Silicon Mac | `deploy.sh` already handles this with `--platform linux/amd64` |
| Cloud Run can't reach Cloud SQL | VPC egress misconfigured | Verify `--network`, `--subnet`, `--vpc-egress=private-ranges-only` flags |
| `permission denied` on secrets | Service account missing role | Grant `roles/secretmanager.secretAccessor` to `n8n-app@` SA |
| Container fails health check | n8n can't connect to DB on startup | Check DB password in Secret Manager matches Cloud SQL user |
| Image rejected by Cloud Run | Image from unsupported registry | Must use GCR, Artifact Registry, or Docker Hub — `deploy.sh` handles this |
