# ShopCloud Security Hardening

## 1. Identity & Access Management

### IRSA (IAM Roles for Service Accounts)
- Every EKS pod uses a dedicated IAM role scoped to minimum required permissions
- No shared IAM roles between services
- Roles are restricted to their specific namespace + service account via OIDC condition
- Rotate IAM credentials are never used — all AWS API access is via IRSA tokens

### Cognito
- Customer pool: MFA optional, password complexity enforced (12 chars, mixed case, symbols)
- Admin pool: MFA mandatory (TOTP), 16-char minimum password, 1-day temp password validity
- Advanced Security Mode: ENFORCED (blocks compromised credentials, suspicious sign-ins)
- Access tokens expire in 1h (customers), 8h (admins)

### VPN (Admin Access)
- AWS Client VPN with mutual TLS + MFA
- Admin staff can only reach the internal ALB — no direct pod/node access
- VPN endpoints are logged to CloudWatch

---

## 2. Network Security

### VPC Segmentation (3-tier)
```
Public subnets   → ALB only (no EC2 instances have public IPs)
Private subnets  → EKS nodes, Lambda (outbound via NAT GW)
Data subnets     → RDS, ElastiCache (no internet route at all)
```

### Security Groups (least-privilege)
- EKS nodes → RDS: port 5432 only
- EKS nodes → Redis: port 6379 only
- Lambda → SQS/S3/SES: port 443 (HTTPS) only
- ALB → EKS nodes: port 3001–3005 only
- No 0.0.0.0/0 ingress rules on any resource

### Kubernetes Network Policies
- Default: deny all ingress and egress in the `shopcloud` namespace
- Each service has an explicit policy allowing only its required ports/peers
- Prometheus scraping allowed from the `monitoring` namespace only

### WAF Rules (CloudFront)
- AWS Managed Rules: CommonRuleSet, KnownBadInputs, SQLiRuleSet
- Rate limiting: 2,000 requests per IP per 5 minutes
- Custom header (X-Origin-Verify) prevents direct ALB access, bypassing CloudFront/WAF

### IMDSv2 Enforced
- All EC2 node launch templates require IMDSv2 (`http_tokens = required`)
- hop limit = 1 (prevents container workloads from accessing IMDS)

---

## 3. Data Encryption

| Layer | Mechanism |
|-------|-----------|
| Data in transit | TLS 1.2+ enforced everywhere (ALB, RDS `rds.force_ssl`, Redis `transit_encryption_enabled`, S3 deny-non-TLS policy) |
| EBS volumes | Encrypted with KMS customer-managed key |
| RDS | Storage encryption with CMK, Performance Insights with CMK |
| ElastiCache | `at_rest_encryption_enabled = true`, auth token |
| S3 | SSE-KMS with bucket key enabled |
| EKS secrets | Encrypted with KMS via cluster `encryption_config` |
| ECR images | Encrypted with KMS |
| SQS messages | SSE with KMS |
| CloudWatch Logs | Encrypted with KMS |

### KMS Key Policy
- Key rotation enabled (annual automatic)
- Multi-region key for DR replication
- Least-privilege: only specific service principals can use the key

---

## 4. Container Security

### Dockerfile Best Practices
- Multi-stage builds (deps → runner) — no dev tools in final image
- Non-root user (UID 1001) in all images
- No secrets in image layers or environment variables at build time

### Kubernetes Pod Security
- `securityContext.runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- `capabilities.drop: [ALL]`
- `seccompProfile: RuntimeDefault`
- Namespace-level Pod Security Standards: `restricted`

### Image Scanning
- ECR scan on push enabled for all repositories
- Trivy scan runs in CI/CD pipeline — blocks on CRITICAL severity
- Lifecycle policies expire untagged images after 7 days

---

## 5. Secrets Management

- All secrets stored in AWS Secrets Manager (never in environment files, Git, or Docker images)
- Pods access secrets via IRSA → Secrets Manager API (or External Secrets Operator)
- Database passwords, Redis auth token, and Cognito client secrets are in Secrets Manager
- Terraform sensitive variables are passed via environment (`TF_VAR_*`) — never in `.tfvars` files committed to Git
- `.gitignore` blocks: `terraform.tfvars`, `*.pem`, `.env*`, `*.key`

---

## 6. Audit & Compliance

### CloudTrail
- Organization-level trail enabled, multi-region, log file validation on
- Logs stored in dedicated S3 bucket with MFA-delete enabled

### VPC Flow Logs
- ALL traffic logged to CloudWatch Logs (30-day retention)
- Enables forensics and anomaly detection

### EKS Audit Logs
- All control plane log types enabled: api, audit, authenticator, controllerManager, scheduler
- Logs shipped to CloudWatch Logs

### RDS Logs
- PostgreSQL logs, slow queries (>1s), connection logs enabled
- Logs exported to CloudWatch

---

## 7. Dependency Management

- `npm audit` runs on every PR — blocks on HIGH/CRITICAL
- Dependabot configured for all services
- Lambda layers and Node.js runtime kept updated (auto minor version upgrade)

---

## 8. Incident Response Checklist

1. **Credential compromise**: Revoke IRSA role, rotate Cognito client secret, invalidate all user sessions via Cognito `GlobalSignOut`
2. **Data breach**: Enable RDS enhanced monitoring, check VPC Flow Logs, notify via SNS, engage AWS Support
3. **DDoS**: Shield Advanced auto-engages; escalate to AWS WAF emergency rate rules
4. **Pod compromise**: `kubectl cordon` the node, drain it, trigger new node from ASG, review audit logs
5. **Bad deployment**: CI/CD pipeline auto-rolls back on failed rollout or smoke test; manual: `kubectl rollout undo deployment/<svc> -n shopcloud`
