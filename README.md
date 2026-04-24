# ShopCloud — Phase 2 & 3 Deliverable

## Project Structure

```
ShopCloud/
├── services/              # Five microservices (Node.js/Express)
│   ├── catalog/           # Product catalog — CRUD, paginated search, PostgreSQL
│   ├── cart/              # Shopping cart — Redis-backed, TTL 7 days
│   ├── checkout/          # Order processing — DB transaction + SQS publish
│   ├── auth/              # Authentication — AWS Cognito wrapper
│   └── admin/             # Admin ops — orders management, metrics summary
├── lambda/
│   └── invoice-generator/ # PDF invoice generation → S3 → SES email
├── db/
│   └── 001_init.sql       # Database schema + seed data
├── terraform/
│   ├── modules/           # Reusable modules: vpc, eks, rds, elasticache,
│   │   │                  #   cognito, ecr, sqs, lambda, s3, cloudfront,
│   │   │                  #   kms, irsa
│   └── environments/
│       ├── dev/           # Dev environment (single-AZ, smaller instances)
│       └── prod/          # Prod environment (Multi-AZ, cross-region DR)
├── k8s/
│   ├── base/              # Deployments, Services, HPAs, NetworkPolicies,
│   │   │                  #   Ingresses, KEDA ScaledObject
│   └── overlays/
│       ├── dev/           # 1 replica, dev image tags
│       └── prod/          # 3 replicas, prod image tags, higher resource limits
├── .github/workflows/
│   ├── dev-pipeline.yml   # Push to develop → test → build → scan → deploy dev
│   ├── prod-pipeline.yml  # Push to main → test → build → manual approval → deploy prod
│   └── pr-checks.yml      # PR → Terraform fmt, K8s lint, npm audit
├── monitoring/
│   ├── prometheus/        # kube-prometheus-stack values, PrometheusRule alerts
│   ├── grafana/           # Dashboard JSON for service overview
│   └── cloudwatch/        # CloudWatch alarms (ALB, RDS, Redis, Lambda, CloudFront)
├── security/
│   └── SECURITY_HARDENING.md  # Complete security posture documentation
├── scripts/
│   ├── deploy.sh          # Manual deployment helper
│   ├── rollback.sh        # Manual rollback (kubectl rollout undo)
│   └── localstack-init.sh # Local AWS emulation setup
└── docker-compose.yml     # Full local dev stack (Postgres + Redis + all services + LocalStack + Prometheus + Grafana)
```

---

## Phase 2 — Running Locally

### Prerequisites
- Docker & Docker Compose
- Node.js 20+

```bash
# Start all services locally
docker-compose up --build

# API endpoints
curl http://localhost:3001/api/v1/products   # catalog
curl http://localhost:3002/health            # cart
curl http://localhost:3003/health            # checkout
curl http://localhost:3004/health            # auth
curl http://localhost:3005/health            # admin

# Prometheus metrics
open http://localhost:9090

# Grafana (admin/admin)
open http://localhost:3000
```

### Running Tests

```bash
cd services/catalog && npm ci && npm test
cd services/cart    && npm ci && npm test
cd services/checkout && npm ci && npm test
```

---

## Phase 2 — Infrastructure Deployment (AWS)

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.6
- kubectl, helm

### 1. Bootstrap state backend (one-time)

```bash
aws s3 mb s3://shopcloud-terraform-state-prod --region us-east-1
aws dynamodb create-table \
  --table-name shopcloud-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Deploy infrastructure

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

export TF_VAR_db_password="<strong-password>"
export TF_VAR_redis_auth_token="<token>"
export TF_VAR_origin_verify_secret="<secret>"

terraform init
terraform plan
terraform apply
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --name shopcloud-prod --region us-east-1
```

### 4. Install cluster add-ons

```bash
# AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=shopcloud-prod

# KEDA
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda -n keda --create-namespace

# Monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/prometheus/values.yaml
```

### 5. Deploy application

```bash
# Update REPLACE_ME placeholders in k8s/base/ with actual values, then:
kubectl apply -k k8s/overlays/prod
```

---

## Phase 2 — CI/CD Pipeline

### How it works

| Branch | Pipeline | Steps |
|--------|----------|-------|
| Any PR → `develop` | pr-checks | Terraform fmt, K8s lint, npm audit |
| Push to `develop` | dev-pipeline | Test → Scan → Build → Push ECR → Deploy dev |
| Any PR → `main` | prod-pipeline | Test + Terraform plan posted to PR |
| Push to `main` | prod-pipeline | Test → Build → **Manual approval** → Deploy prod → Smoke test → Auto-rollback if failed |

### Required GitHub Secrets

```
AWS_DEV_DEPLOY_ROLE_ARN      — IAM role for dev deployments (OIDC)
AWS_PROD_BUILD_ROLE_ARN      — IAM role for prod image builds
AWS_PROD_DEPLOY_ROLE_ARN     — IAM role for prod deployments
AWS_PROD_TERRAFORM_ROLE_ARN  — IAM role for Terraform plan
ECR_REGISTRY                 — ECR registry URL (123456789012.dkr.ecr.us-east-1.amazonaws.com)
DEV_API_URL                  — Dev API base URL for smoke tests
PROD_API_URL                 — Prod API base URL for smoke tests
SLACK_WEBHOOK_URL            — Slack incoming webhook
TF_DB_PASSWORD               — RDS password for Terraform plan
TF_REDIS_TOKEN               — Redis auth token
TF_ORIGIN_SECRET             — CloudFront origin verify secret
```

### Rollback Instructions

**Automatic**: The production pipeline rolls back automatically if the rollout or smoke tests fail.

**Manual**:
```bash
# Via script
./scripts/rollback.sh prod

# Or directly
kubectl rollout undo deployment/catalog -n shopcloud
kubectl rollout undo deployment/cart -n shopcloud
# ... repeat for each service

# To roll back to a specific revision
kubectl rollout undo deployment/catalog -n shopcloud --to-revision=2
```

---

## Phase 3 — Monitoring & Observability

### What's monitored

| Signal | Tool | Coverage |
|--------|------|----------|
| Service request rate, latency (p99), error rate | Prometheus + Grafana | All 5 services |
| Pod health, restarts, HPA saturation | Prometheus + kube-state-metrics | EKS cluster-wide |
| ALB 5xx rate, p99 latency | CloudWatch Alarms | Public + internal ALB |
| RDS CPU, connections, free storage | CloudWatch Alarms | Primary RDS |
| Redis memory, connections | CloudWatch Alarms | ElastiCache cluster |
| SQS queue depth, DLQ messages | CloudWatch Alarms | Invoice pipeline |
| Lambda errors, duration | CloudWatch Alarms | Invoice generator |
| CloudFront 5xx rate | CloudWatch Alarms | CDN layer |

### Alerting flow
```
Prometheus AlertManager → Slack #shopcloud-alerts (warning)
                        → Slack #shopcloud-critical (critical/DLQ)
CloudWatch Alarm        → SNS topic → Email + Slack
```

### Accessing dashboards
```bash
# Port-forward Grafana
kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring
open http://localhost:3000  # admin / <password from values.yaml>

# Port-forward Prometheus
kubectl port-forward svc/kube-prometheus-kube-prome-prometheus 9090:9090 -n monitoring
open http://localhost:9090
```

---

## Phase 3 — Security Hardening

See [security/SECURITY_HARDENING.md](security/SECURITY_HARDENING.md) for the full security posture.

**Key controls:**
- 3-tier VPC with strict security group rules and Kubernetes NetworkPolicies
- IRSA per-service with least-privilege IAM policies
- All secrets in Secrets Manager — no env vars with credentials in images or Git
- TLS everywhere, KMS encryption for all data at rest
- IMDSv2 enforced on EKS nodes
- WAF + rate limiting + Shield Advanced on CloudFront
- Pod Security Standards: `restricted` profile on all workload pods
- Trivy image scanning blocks CRITICAL CVEs in CI/CD
- Admin access gated behind Client VPN + MFA + separate Cognito pool
