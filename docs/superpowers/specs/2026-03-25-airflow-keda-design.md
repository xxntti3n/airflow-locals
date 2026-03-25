# Local Airflow on Kind with KEDA Auto-scaling

**Date:** 2026-03-25
**Status:** Approved

## Overview

A fully self-contained Airflow 3.x development environment running on Kind (Kubernetes in Docker), with Celery executor and KEDA-based hybrid auto-scaling for workers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kind Cluster                             │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Kubernetes Namespace                     │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐   │ │
│  │  │ Airflow     │  │ PostgreSQL   │  │ Redis           │   │ │
│  │  │ Webserver   │  │ (Metadata)   │  │ (Celery Broker) │   │ │
│  │  │ + Scheduler │  │              │  │                 │   │ │
│  │  └─────────────┘  └──────────────┘  └─────────────────┘   │ │
│  │                                                             │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │         Airflow Workers (CeleryExecutor)             │  │ │
│  │  │                                                       │  │ │
│  │  │   ┌───────┐  ┌───────┐  ┌───────┐  (scaled by KEDA)  │  │ │
│  │  │   │Worker │  │Worker │  │Worker │                    │  │ │
│  │  │   └───────┘  └───────┘  └───────┘                    │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  │                           ▲                                 │ │
│  │                           │                                 │ │
│  │                    ┌─────────────┐                         │ │
│  │                    │    KEDA     │                         │ │
│  │                    │  ScaledObject│                         │ │
│  │                    └─────────────┘                         │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Implementation | Purpose |
|-----------|----------------|---------|
| Kind Cluster | `kind create cluster` | Local Kubernetes runtime |
| Airflow | Official Helm Chart (3.x+) | DAG orchestration platform |
| PostgreSQL | Helm-chart dep sub-chart | Metadata database |
| Redis | Helm-chart dep sub-chart | Celery message broker |
| KEDA | Helm chart install | Auto-scale workers |
| Example DAGs | ConfigMap or Git sync | Sample DAGs for development |

## KEDA Scaling Strategy (Hybrid)

**Primary: Queue-based**
- Scaler: `redis` scaler type
- Target: Redis list length (pending Celery tasks)
- Thresholds: Scale from 0 to N workers based on queue depth
- Triggers: `queueLength` > X adds workers

**Safeguards: CPU/Memory**
- HPA-style limits on max replicas
- Resource requests/limits on worker pods
- Fallback scale-down if resources constrained

## Data Flow

1. **Scheduler** evaluates which tasks are ready to run (schedule, dependencies)
2. **CeleryExecutor** (invoked by Scheduler):
   - Creates TaskInstance in PostgreSQL with state `"queued"`
   - Sends task message to **Redis** (Celery broker)
3. **KEDA** monitors Redis queue depth via scaler
4. **Worker** (Celery worker):
   - Receives task from Redis
   - Updates PostgreSQL TaskInstance state to `"running"`
   - Executes the task
   - Updates PostgreSQL with final state (`"success"` / `"failed"`)
5. When Redis queue empties + cooldown expires, KEDA scales workers to zero

## Deployment Structure

```
airflow-locals/
├── kind/
│   └── cluster.yaml           # Kind cluster config
├── helm/
│   ├── airflow-values.yaml    # Airflow Helm values
│   └── keda-values.yaml       # KEDA Helm values
├── dags/
│   └── examples/              # Example DAGs
├── scripts/
│   ├── setup.sh               # Create cluster & install
│   ├── port-forward.sh        # Access Airflow UI
│   └── teardown.sh            # Destroy cluster
└── README.md                  # Setup instructions
```

## Configuration Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Kubernetes | Kind | Faster startup, lighter, runs in Docker |
| DAGs | Example DAGs | Start with samples, develop locally |
| Database/Broker | PostgreSQL + Redis | Production-standard stack |
| Deployment | Inside Kind | Self-contained, simpler architecture |
| Scaling | Hybrid (queue + CPU/Memory) | Responsive with safeguards |
| Deployment method | Helm charts | Industry standard, configurable |
| Airflow version | 3.x+ | Latest stable with better K8s support |
| UI access | Port-forward | Secure, simple for local dev |

## Success Criteria

- [ ] Kind cluster creates successfully
- [ ] Airflow deploys with CeleryExecutor
- [ ] PostgreSQL and Redis run as in-cluster pods
- [ ] KEDA ScaledObject configured for Redis queue depth
- [ ] Workers scale from 0 to N based on queue
- [ ] Workers scale to zero when idle
- [ ] Example DAGs run successfully
- [ ] Airflow UI accessible via port-forward
- [ ] Teardown script cleanly destroys cluster
