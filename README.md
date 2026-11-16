# Platform engineer assessment

## Install and run

From the repository root:

```bash
./up.sh              # Build images, create the cluster and deploy everything
./run-image-job.sh   # Run the nightly job now
./down.sh            # Delete the cluster and all its data
```

`up.sh` also loads three sample images. Rerunning it rebuilds and redeploys while keeping existing passwords and data. The first run needs internet access and takes longer while dependencies download.

| Service | Local URL |
|---|---|
| App | http://localhost:8080 |
| Keycloak | http://localhost:8180 |
| Prometheus | http://localhost:9090 |
| Alertmanager | http://localhost:9093 |

These ports must be free. If the old Compose setup is running, stop it with `docker compose down` first.

Open the app, click login and use `user` / `password`. Draw a box around London and search. The image job runs daily at **02:00 UTC**; view a manual run with `kubectl -n assessment logs -f job/<name>` using the name printed by the script.

## How it fits together

```text
Browser ── page/search ──> API
   │                       │ signing keys
   └── login ──> Keycloak <─┘

Image CronJob ── reads images ──> MinIO
      └──── saves dimensions/brightness/status ──> Postgres

Prometheus ── scrapes ──> API, Keycloak, kube-state-metrics
      └──── alerts ──> Alertmanager
```

All services run in kind. Postgres and MinIO serve only the image job; the API uses neither.

## Choices and reasons

- **kind and plain manifests:** reproducible local Kubernetes without a registry. Kustomize keeps deployment simple; Helm installs the existing Prometheus stack.
- **Small, non-root images:** a multi-stage Java build keeps Maven out of the API runtime. Python and Pillow keep image analysis straightforward.
- **Persistent volumes and generated secrets:** Postgres and MinIO data survive pod restarts. Setup generates service passwords once and reuses them.
- **Safe reruns:** ETags skip unchanged images, a Postgres advisory lock prevents overlapping processing, and each result commits separately. Downloads get three attempts; broken images are recorded and skipped until replaced.
- **Probes, resource limits and alerts:** detect unhealthy services and constrain resource use. Alerts cover API/Keycloak availability, search errors above 5%, failed jobs and no successful job for 26 hours. `FAULT_ERROR_RATE` allows deliberate search failures for testing.

## Gaps and next steps

- Add automated job tests for retries, skipping, concurrency and recovery. CI currently runs Java tests and builds both images.
- Guard against oversized images exhausting memory; stop early during storage outages and handle shutdown cleanly.
- Replace Keycloak dev mode and temporary storage, restrict database/bucket permissions, and add TLS and NetworkPolicies.
- Add backups, multiple replicas, Postgres/MinIO availability alerts and dashboards. The local setup has no high availability or external paging.

## AWS plan

Keep the workloads on **EKS** to reuse the manifests, CronJob and alert rules. Use Terraform for infrastructure and Kustomize overlays for environment settings.

Replace MinIO with **S3** and Postgres with **Multi-AZ RDS** with automated backups. Give the job bucket access through EKS Pod Identity. Run Keycloak in production mode with its own persistent database.

Put an **ALB** in front, with ACM TLS certificates and Route 53 DNS. Keep nodes and databases in private subnets. Spread API and Keycloak replicas across availability zones; add disruption budgets and API autoscaling.

Publish images to **ECR** through GitHub Actions using OIDC, deploy through Argo CD, and store secrets in Secrets Manager. Keep Prometheus/Alertmanager, connect alerts to the team's paging service, and ship logs to CloudWatch.
