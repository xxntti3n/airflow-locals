# Airflow on Kind with KEDA Auto-scaling

Local Airflow 2.9.x development environment on Kubernetes (Kind) with CeleryExecutor and KEDA-based worker auto-scaling.

## Features

- **Kind** — Kubernetes in Docker for local development
- **Airflow 2.9.x** — Latest stable Airflow with CeleryExecutor
- **PostgreSQL + Redis** — Production-like database and broker
- **KEDA** — Queue-based auto-scaling (0-5 workers)
- **Example DAGs** — Ready-to-run examples

## Quick Start

### Prerequisites

```bash
# Install Kind
brew install kind  # macOS
# or: https://kind.sigs.k8s.io/

# Install kubectl
brew install kubectl  # macOS
# or: https://kubernetes.io/docs/tasks/tools/

# Install Helm
brew install helm  # macOS
# or: https://helm.sh/
```

### Setup

```bash
# Clone and navigate to project
cd airflow-locals

# Run setup
./scripts/setup.sh
```

This will:
1. Create a Kind cluster named `airflow-local`
2. Install KEDA for auto-scaling
3. Install Airflow with CeleryExecutor
4. Configure example DAGs

### Access Airflow UI

```bash
./scripts/port-forward.sh
```

Then open http://localhost:8080

**Default credentials:** `admin` / `admin`

## Architecture

```
Kind Cluster
├── Airflow Webserver/Scheduler (1 replica each)
├── Airflow Workers (0-5 replicas, scaled by KEDA)
├── PostgreSQL (metadata database)
└── Redis (Celery broker)
```

## KEDA Scaling

Workers scale based on **Redis queue depth**:

| Queue Length | Worker Replicas |
|--------------|-----------------|
| 0            | 0               |
| 1            | 1               |
| 5+           | Up to 5         |

**Cooldown:** 5 minutes of idle before scaling down to 0.

## Monitoring

```bash
# Check KEDA ScaledObject status
kubectl get scaledobject -n airflow

# Check HPA status
kubectl get hpa -n airflow

# Check worker pods
kubectl get pods -n airflow -l component=worker

# View KEDA metrics
kubectl describe scaledobject airflow-worker-scaler -n airflow
```

## Testing Auto-scaling

1. Unpause an example DAG in the UI
2. Trigger a DAG run
3. Watch workers scale up:

```bash
watch kubectl get pods -n airflow
```

## Teardown

```bash
./scripts/teardown.sh
```

This deletes the Kind cluster entirely.

## Adding DAGs

Place new DAGs in `dags/examples/`, then:

```bash
# Update ConfigMap
kubectl create configmap airflow-dag-examples \
    --namespace airflow \
    --from-file=dags/examples/ \
    --dry-run=client -o yaml | kubectl apply -f -

# Restart scheduler
kubectl rollout restart deployment airflow-scheduler -n airflow
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl describe pod <pod-name> -n airflow
kubectl logs <pod-name> -n airflow
```

**Workers not scaling?**
```bash
# Check KEDA is installed
kubectl get pods -n keda

# Check ScaledObject
kubectl describe scaledobject airflow-worker-scaler -n airflow
```

**Port-forward not working?**
```bash
# Check webserver service
kubectl get svc -n airflow

# Check pod is ready
kubectl get pods -n airflow -l component=webserver
```

## License

MIT License - see [LICENSE](LICENSE) for details.