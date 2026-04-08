# Cloud deployment — E-Governance microservices platform

**New to AWS?** Use the step-by-step guide: **[docs/AWS_DEPLOYMENT_BEGINNER.md](./docs/AWS_DEPLOYMENT_BEGINNER.md)** (account, IAM, EKS, ECR, kubectl, Load Balancer).

---

This project is **cloud-native**: each component is a **container** that you can run on **managed Kubernetes** (or similar) with **managed data stores** and a **public entry point** (load balancer + TLS).

This guide maps **what you already have** (`Dockerfile`s, `docker-compose.yml`, `k8s/`) to a **production-style cloud** layout. It is not a single “click deploy” script—cloud accounts differ—but it is the checklist and patterns teams use.

---

## 1. Target architecture on cloud

```
Internet → [TLS] → Load balancer / Ingress → API Gateway (8000)
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
  Citizen Service   Notification    Document Service
        │               │               │
        ▼               ▼               ▼
  Managed PostgreSQL  Managed Redis   Object storage or PVC
  (or RDS / Cloud SQL) (ElastiCache / Memorystore)
```

- **Users and browsers** only hit the **API gateway** (HTTPS).
- **WebSockets** (`/notifications/ws`) need a load balancer or Ingress that supports **long-lived connections** (timeouts, sticky sessions optional).
- **State**: PostgreSQL (citizens, users, requests), Redis (pub/sub + optional cache), disk or object storage (uploaded files).

---

## 2. Recommended path: Kubernetes on a cloud provider

Use the manifests in **`k8s/`** on:

| Provider | Managed Kubernetes |
|----------|-------------------|
| **AWS** | [Amazon EKS](https://docs.aws.amazon.com/eks/) |
| **Google Cloud** | [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine) |
| **Microsoft Azure** | [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/azure/aks/) |

**High-level steps**

1. Create a cluster (EKS / GKE / AKS).
2. **Container registry**: build images and push to **ECR** (AWS), **Artifact Registry** (GCP), or **ACR** (Azure).  
   Replace image names in `k8s/*.yaml` from `egov-*:latest` to something like:  
   `123456789.dkr.ecr.region.amazonaws.com/egov-api-gateway:v1`.
3. **Secrets**: do **not** commit real secrets. Use:
   - cloud **Secret Manager** + CSI driver, or  
   - `kubectl create secret` / Sealed Secrets / External Secrets Operator.
4. **`kubectl apply -f k8s/`** (after editing secrets and images), or use **Helm** / **GitOps** (Argo CD, Flux) for repeatability.
5. **Ingress + TLS**: install an Ingress controller (e.g. **nginx-ingress**, **AWS Load Balancer Controller**) and use **cert-manager** with **Let’s Encrypt** for HTTPS.
6. **DNS**: point your domain (e.g. `egov.example.gov`) to the load balancer IP / hostname.

See **`k8s/README.md`** for local/Docker Desktop flow; the same manifests apply on cloud after you change **images** and **secrets**.

---

## 3. Managed databases (production)

For real workloads, run **PostgreSQL** and **Redis** as **managed services** instead of Pods in `03-postgres.yaml` / `04-redis.yaml`.

### PostgreSQL

- **AWS**: [RDS for PostgreSQL](https://aws.amazon.com/rds/postgresql/)
- **GCP**: [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- **Azure**: [Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/)

**Citizen-service** needs a connection string in **`DATABASE_URL`**, same format as today:

`postgresql+asyncpg://USER:PASSWORD@HOST:5432/DBNAME`

Put it in a **Secret** (same key you use today: `database-url` in `k8s/01-secrets.yaml` pattern).  
**Remove or scale down** the in-cluster `postgres` Deployment if you switch to managed DB.

### Redis

- **AWS**: [ElastiCache for Redis](https://aws.amazon.com/elasticache/redis/)
- **GCP**: [Memorystore for Redis](https://cloud.google.com/memorystore/docs/redis)
- **Azure**: [Azure Cache for Redis](https://learn.microsoft.com/azure/azure-cache-for-redis/)

Set:

- **Notification service**: `REDIS_URL=redis://:PASSWORD@HOST:6379/0` (as required by your provider; TLS may need `rediss://`).
- **Citizen service** (cache): `REDIS_URL` to a **separate DB index** (e.g. `/1`) or a second instance—same pattern as Docker Compose.

Update **`k8s/02-configmap.yaml`** or use Secrets for Redis URLs if they contain passwords.

---

## 4. Document uploads (files)

Today **document-service** uses a **PVC** (`k8s/05-document-service.yaml`). On cloud that maps to **EBS** / **Persistent Disk** / **Azure Disk** via your storage class—fine for a single replica.

For **multiple replicas** or **disaster recovery**, move to **object storage**:

- **AWS S3**, **GCS**, **Azure Blob** — would require **code changes** in document-service (not in repo today).  
Until then: **one replica** of document-service + PVC, or accept that files live on one node’s disk.

---

## 5. Configuration checklist (any cloud)

| Item | Purpose |
|------|--------|
| **`JWT_SECRET_KEY`** | Same value in **gateway** and **citizen-service**; long random string. |
| **`DATABASE_URL`** | Managed Postgres URL for **citizen-service**. |
| **`REDIS_URL`** | Notification + citizen cache (see above). |
| **`CITIZEN_SERVICE_URL`**, **`NOTIFICATION_SERVICE_URL`**, **`DOCUMENT_SERVICE_URL`** | Internal K8s DNS: `http://citizen-service:8001` etc. (already in ConfigMap). |
| **`RESET_PASSWORD_BASE_URL`** | Public HTTPS URL to dashboard, e.g. `https://egov.example.gov/dashboard` — in Secret for **citizen-service**. |
| **SMTP** (`SMTP_*`, `EMAIL_FROM`) | For welcome / status / reset emails. |
| **Ingress host + TLS** | Public URL and certificates. |
| **WebSocket timeouts** | Ingress/proxy must allow long-lived connections (see `k8s/09-ingress.yaml` annotations for nginx). |

---

## 6. AWS-specific sketch (EKS + RDS + ElastiCache)

1. **EKS cluster** + node group (or Fargate profile—mind PVC/Fargate limits).
2. **ECR** repositories for the four app images; CI/CD pushes on tag.
3. **RDS PostgreSQL** in same VPC as EKS; security group allows **citizen-service** → 5432.
4. **ElastiCache Redis** in VPC; security groups for **notification-service** and **citizen-service**.
5. **AWS Load Balancer Controller** + **Ingress** + **ACM** certificate for HTTPS.
6. Apply **`k8s/`** with: images → ECR, `database-url` / Redis URLs / JWT / SMTP in **Secrets**, optionally delete in-cluster Postgres/Redis Deployments once managed services are wired.

---

## 7. GCP-specific sketch (GKE + Cloud SQL + Memorystore)

1. **GKE** Autopilot or Standard cluster.
2. **Artifact Registry** for images.
3. **Cloud SQL** (PostgreSQL) with **private IP** or **Cloud SQL Auth Proxy** sidecar; set `DATABASE_URL` accordingly.
4. **Memorystore (Redis)**; VPC connectivity from GKE.
5. **GKE Ingress** + **Google-managed certificate** or cert-manager.
6. Same manifest edits as above.

---

## 8. Azure-specific sketch (AKS + Flexible Server + Redis)

1. **AKS** cluster.
2. **Azure Container Registry (ACR)**; `az acr build` or pipeline push.
3. **Azure Database for PostgreSQL – Flexible Server**; firewall / private link to AKS.
4. **Azure Cache for Redis**.
5. **Application Gateway** or **NGINX Ingress** + **Key Vault** for secrets (optional).
6. Same manifest edits as above.

---

## 9. Alternative: ECS / Cloud Run (no Kubernetes)

- **AWS ECS/Fargate**: one task definition per service + **Service Connect** or Cloud Map for DNS; RDS + ElastiCache; **ALB** for gateway (WebSocket support on ALB).
- **Cloud Run**: better for **stateless HTTP**; **WebSockets** and **long-lived Redis pub/sub** to all tabs are trickier—Kubernetes is usually simpler for this stack.

---

## 10. Security reminders

- Restrict **Ingress** to HTTPS only; set **HSTS** at the edge if policy allows.
- Narrow **CORS** on the gateway when you know the production dashboard origin (today it allows `*`).
- Rotate **JWT** and **database** credentials; use **least privilege** DB users.
- Enable **audit logging** on the cloud account and **backup** managed Postgres (and document storage policy).

---

## 11. What you already have in-repo

| Asset | Use on cloud |
|-------|----------------|
| `services/*/Dockerfile` | Build and push to your registry |
| `k8s/*.yaml` | Base for EKS/GKE/AKS; swap images + secrets + optional remove Postgres/Redis Pods |
| `docker-compose.yml` | Local/dev only (not for production cloud) |

For **first cloud deploy**, a practical order is: **GKE or EKS + push images + apply k8s + Ingress + TLS + managed Postgres + managed Redis**, then tune **RESET_PASSWORD_BASE_URL** and SMTP.

---

*If you tell us your target (**AWS**, **GCP**, or **Azure**), we can add a minimal **Terraform** or **step-by-step** file tailored to that provider next.*
