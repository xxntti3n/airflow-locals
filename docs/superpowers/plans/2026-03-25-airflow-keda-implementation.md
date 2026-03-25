# Airflow on Kind with KEDA Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a fully self-contained Airflow 2.9.x development environment on Kind with CeleryExecutor and KEDA hybrid auto-scaling.

**Architecture:** Kind cluster runs Airflow (Webserver, Scheduler, Workers), PostgreSQL, Redis, and KEDA. Workers scale 0→N based on Redis queue depth with CPU/memory safeguards. All components access via port-forward.

**Tech Stack:** Kind, Airflow 2.9.x (Helm), PostgreSQL, Redis, KEDA (Helm), Bash scripts

**Note:** Using Airflow 2.9.x as Airflow 3.x Helm charts are not yet generally available. Upgrade path to 3.x will be straightforward once released.

---

## File Structure

```
airflow-locals/
├── kind/
│   └── cluster.yaml           # Kind cluster config (port mapping, RBAC)
├── helm/
│   ├── airflow-values.yaml    # Airflow Helm chart values (executor, dags, KEDA config)
│   └── keda-values.yaml       # KEDA Helm chart values (minimal)
├── dags/
│   └── examples/
│       ├── __init__.py
│       ├── example_bash_operator.py    # Simple bash task DAG
│       └── example_task_flow.py        # Multi-task dependency DAG
├── scripts/
│   ├── setup.sh               # Create Kind cluster, install Helm charts
│   ├── port-forward.sh        # Port-forward Airflow webserver (8080)
│   └── teardown.sh            # Delete cluster
├── docs/
│   └── superpowers/
│       ├── specs/
│       │   └── 2026-03-25-airflow-keda-design.md
│       └── plans/
│           └── 2026-03-25-airflow-keda-implementation.md
└── README.md                  # Setup and usage instructions
```

---

## Chunk 1: Project Foundation and Kind Cluster

### Task 1: Create Kind cluster configuration

**Files:**
- Create: `kind/cluster.yaml`

**Purpose:** Define Kind cluster with port mappings for NodePort access (for Airflow webserver if needed later) and proper RBAC for KEDA.

- [ ] **Step 1: Create Kind cluster config**

```yaml
# kind/cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: airflow-local
nodes:
  - role: control-plane
    image: kindest/node:v1.29.0
    extraPortMappings:
      # Optional: for future NodePort access
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP
    extraMounts:
      # Mount DAGs directory for local development
      - hostPath: ./dags
        containerPath: /dags
        readOnly: true
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p kind helm dags/examples scripts
```

- [ ] **Step 3: Verify file created**

```bash
cat kind/cluster.yaml
```

Expected: Output matches the YAML above

- [ ] **Step 4: Commit**

```bash
git add kind/cluster.yaml
git commit -m "feat: add Kind cluster configuration

- Single control-plane node
- Port mapping for potential NodePort access
- Mount point for local DAGs directory
"
```

---

### Task 2: Create Helm values for KEDA

**Files:**
- Create: `helm/keda-values.yaml`

**Purpose:** Minimal KEDA installation with required RBAC for scaling Airflow workers.

- [ ] **Step 1: Create KEDA Helm values**

```yaml
# helm/keda-values.yaml
# Minimal KEDA installation for Airflow worker autoscaling

# Install KEDA core components
installKeda: true

# Do not install KEDA Operator admission webhooks (not needed for local dev)
admissionWebhooks:
  enabled: false

# Metrics server integration (Kind has built-in metrics)
serviceAccount:
  create: true

# RBAC for KEDA to manage ScaledObjects
featureFlag:
  enabledFeatures:
    - "scaledjob"
```

- [ ] **Step 2: Verify file created**

```bash
cat helm/keda-values.yaml
```

Expected: Output matches the YAML above

- [ ] **Step 3: Commit**

```bash
git add helm/keda-values.yaml
git commit -m "feat: add KEDA Helm values

- Core KEDA installation
- RBAC for ScaledObject management
- ScaledJob feature enabled
"
```

---

### Task 3: Create Helm values for Airflow with KEDA integration

**Files:**
- Create: `helm/airflow-values.yaml`

**Purpose:** Complete Airflow configuration with CeleryExecutor, PostgreSQL, Redis, and KEDA ScaledObject for worker autoscaling.

- [ ] **Step 1: Create Airflow Helm values**

```yaml
# helm/airflow-values.yaml
# Airflow 3.x with CeleryExecutor and KEDA autoscaling

# Airflow version
airflowVersion: "2.9.0"  # Use stable 2.9.x as 3.x Helm chart may not be available

# Executor configuration
executor: "CeleryExecutor"

# --- Environment Variables ---
env:
  - name: AIRFLOW__CORE__LOAD_EXAMPLES
    value: "False"
  - name: AIRFLOW__WEBSERVER__EXPOSE_CONFIG
    value: "True"
  - name: AIRFLOW__WEBSERVER__AUTHENTICATE
    value: "False"

# --- DAGs ---
# Load DAGs from ConfigMap created by setup script
dags:
  persistence:
    enabled: true
    # Use existing ConfigMap created by setup script
    existingClaim: null
  gitSync:
    enabled: false

# Volume mount for DAGs from ConfigMap
extraVolumeMounts:
  - name: dag-files
    mountPath: /opt/airflow/dags
    readOnly: true
    subPath: null

extraVolumes:
  - name: dag-files
    configMap:
      name: airflow-dag-examples
      items:
        - key: example_bash_operator.py
          path: example_bash_operator.py
        - key: example_task_flow.py
          path: example_task_flow.py
        - key: __init__.py
          path: __init__.py

# --- PostgreSQL Database ---
postgresql:
  enabled: true
  image:
    repository: postgres
    tag: "15"
  postgresqlUsername: postgres
  postgresqlPassword: airflow
  postgresqlDatabase: airflow
  persistence:
    enabled: true
    size: 1Gi

# --- Redis (Celery Broker) ---
redis:
  enabled: true
  image:
    repository: redis
    tag: "7-alpine"
  master:
    persistence:
      enabled: true
      size: 512Mi

# --- Celery Worker Configuration ---
workers:
  # Use KEDA for autoscaling
  autoscaling:
    enabled: true

  # Minimal worker pod configuration
  replicas: 0  # KEDA will manage replicas

  # KEDA ScaledObject configuration
  keda:
    # Enable KEDA autoscaling
    enabled: true

    # Redis scaler configuration
    # Note: This requires KEDA to be installed first
    scaledObject:
      # pollingInterval: Seconds between checks
      pollingInterval: 15
      # cooldownPeriod: Seconds after last trigger before scaling to zero
      cooldownPeriod: 300
      # minReplicaCount: Minimum workers (0 for serverless)
      minReplicaCount: 0
      # maxReplicaCount: Maximum workers
      maxReplicaCount: 5
      triggers:
        - type: redis
          metadata:
            address: redis-master:6379
            listName: default
            listLength: "5"  # Scale when queue has 5+ tasks
            activationListLength: "1"  # Activate when 1+ tasks in queue
            # Disable TLS for local development
            enableTLS: "false"
            # No authentication for local Redis
            # If Redis requires password, add: redisPasswordFromEnv: REDIS_PASSWORD

  # Worker resources (CPU/Memory safeguards)
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2048Mi

  # Worker command
  command:
    - "/usr/bin/dumb-init"
    - "--"
    - "/entrypoint"
    - "celery"
    - "worker"

# --- Scheduler ---
scheduler:
  replicas: 1
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1536Mi

  # Wait for Redis and PostgreSQL
  extraContainers: |

# --- Webserver ---
webserver:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Service configuration for port-forward
  service:
    type: ClusterIP
    ports:
      - name: airflow-ui
        port: 8080

# --- Statsd (Prometheus exporter) ---
statsd:
  enabled: false

# --- PGBadger (PostgreSQL logging) ---
pgbouncer:
  enabled: false

# --- Ingress ---
ingress:
  enabled: false

# --- PDB (Pod Disruption Budget) ---
podDisruptionBudget:
  enabled: false
```

- [ ] **Step 2: Verify file created**

```bash
cat helm/airflow-values.yaml
```

Expected: Output matches the YAML above

- [ ] **Step 3: Commit**

```bash
git add helm/airflow-values.yaml
git commit -m "feat: add Airflow Helm values with KEDA integration

- CeleryExecutor with PostgreSQL + Redis
- KEDA ScaledObject for queue-based autoscaling (0-5 workers)
- CPU/Memory resource safeguards
- Port-forward UI access
- Minimal production-like setup
"
```

---

## Chunk 2: Example DAGs

### Task 4: Create example DAGs structure

**Files:**
- Create: `dags/examples/__init__.py`
- Create: `dags/examples/example_bash_operator.py`
- Create: `dags/examples/example_task_flow.py`

**Purpose:** Provide working example DAGs that demonstrate Airflow patterns and can be used to test the deployment.

- [ ] **Step 1: Create __init__.py**

```python
# dags/examples/__init__.py
# Example DAGs package
```

- [ ] **Step 2: Create simple bash operator DAG**

```python
# dags/examples/example_bash_operator.py
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id="example_bash_operator",
    start_date=datetime(2025, 1, 1),
    schedule_interval=timedelta(hours=1),
    catchup=False,
    tags=["example", "bash"],
) as dag:
    # Simple task that prints a message
    print_hello = BashOperator(
        task_id="print_hello",
        bash_command="echo 'Hello from Airflow on Kubernetes!'",
    )

    # Task that sleeps briefly (simulates work)
    sleep_task = BashOperator(
        task_id="sleep_task",
        bash_command="sleep 10 && echo 'Slept for 10 seconds'",
    )

    # Task that shows environment info
    show_env = BashOperator(
        task_id="show_env",
        bash_command="echo 'Hostname:' && hostname && echo 'User:' && whoami",
    )

    print_hello >> sleep_task >> show_env
```

- [ ] **Step 3: Create multi-task flow DAG**

```python
# dags/examples/example_task_flow.py
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator

with DAG(
    dag_id="example_task_flow",
    start_date=datetime(2025, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    tags=["example", "dependencies"],
    description="Demonstrates task dependencies and parallel execution",
) as dag:
    # Start node
    start = EmptyOperator(task_id="start")

    # Three parallel tasks
    task_a = BashOperator(
        task_id="task_a",
        bash_command="echo 'Task A executing' && sleep 5",
    )

    task_b = BashOperator(
        task_id="task_b",
        bash_command="echo 'Task B executing' && sleep 8",
    )

    task_c = BashOperator(
        task_id="task_c",
        bash_command="echo 'Task C executing' && sleep 3",
    )

    # Aggregation task
    aggregate = BashOperator(
        task_id="aggregate",
        bash_command="echo 'All parallel tasks completed!'",
    )

    # Final task
    end = EmptyOperator(task_id="end")

    # Define dependencies
    start >> [task_a, task_b, task_c] >> aggregate >> end
```

- [ ] **Step 4: Verify DAGs created**

```bash
ls -la dags/examples/
python3 -m py_compile dags/examples/*.py
```

Expected: Three files listed, no syntax errors

- [ ] **Step 5: Commit**

```bash
git add dags/examples/
git commit -m "feat: add example DAGs

- example_bash_operator: Simple sequential tasks
- example_task_flow: Parallel execution with dependencies
- Demonstrates common Airflow patterns
"
```

---

## Chunk 3: Setup Script

### Task 5: Create setup script

**Files:**
- Create: `scripts/setup.sh`

**Purpose:** Automated setup that creates Kind cluster, installs KEDA, then installs Airflow.

- [ ] **Step 1: Create setup script**

```bash
#!/usr/bin/env bash
# scripts/setup.sh
# Creates Kind cluster and installs Airflow with KEDA

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
CLUSTER_NAME="airflow-local"
AIRFLOW_NAMESPACE="airflow"
KEDA_NAMESPACE="keda"

echo -e "${GREEN}=== Airflow on Kind Setup ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind is not installed${NC}"
    echo "Install from: https://kind.sigs.k8s.io/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed${NC}"
    echo "Install from: https://helm.sh/"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites satisfied${NC}"
echo ""

# Check if cluster already exists
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Cluster '${CLUSTER_NAME}' already exists${NC}"
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting existing cluster...${NC}"
        kind delete cluster --name "${CLUSTER_NAME}"
    else
        echo "Exiting"
        exit 0
    fi
fi

# Create Kind cluster
echo -e "${YELLOW}Creating Kind cluster...${NC}"
kind create cluster \
    --config "${PROJECT_ROOT}/kind/cluster.yaml" \
    --name "${CLUSTER_NAME}"

echo -e "${GREEN}✓ Kind cluster created${NC}"
echo ""

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=ready nodes --all --timeout=300s
echo -e "${GREEN}✓ Cluster is ready${NC}"
echo ""

# Add KEDA Helm repository
echo -e "${YELLOW}Adding KEDA Helm repository...${NC}"
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
echo -e "${GREEN}✓ KEDA repository added${NC}"
echo ""

# Install KEDA
echo -e "${YELLOW}Installing KEDA...${NC}"
kubectl create namespace "${KEDA_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install keda kedacore/keda \
    --namespace "${KEDA_NAMESPACE}" \
    --values "${PROJECT_ROOT}/helm/keda-values.yaml" \
    --wait

echo -e "${GREEN}✓ KEDA installed${NC}"
echo ""

# Wait for KEDA CRDs to be registered
echo -e "${YELLOW}Waiting for KEDA CRDs to be ready...${NC}"
timeout 60 bash -c 'until kubectl get crd scaledobjects.keda.sh &>/dev/null; do sleep 2; done'
echo -e "${GREEN}✓ KEDA CRDs ready${NC}"
echo ""

# Add Airflow Helm repository
echo -e "${YELLOW}Adding Airflow Helm repository...${NC}"
helm repo add apache-airflow https://airflow.apache.org
helm repo update
echo -e "${GREEN}✓ Airflow repository added${NC}"
echo ""

# Create Airflow namespace
echo -e "${YELLOW}Creating Airflow namespace...${NC}"
kubectl create namespace "${AIRFLOW_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Create ConfigMap with example DAGs
echo -e "${YELLOW}Creating ConfigMap for DAGs...${NC}"
kubectl create configmap airflow-dag-examples \
    --namespace "${AIRFLOW_NAMESPACE}" \
    --from-file="${PROJECT_ROOT}/dags/examples/" \
    --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ DAG ConfigMap created${NC}"
echo ""

# Install Airflow
echo -e "${YELLOW}Installing Airflow...${NC}"
helm upgrade --install airflow apache-airflow/airflow \
    --namespace "${AIRFLOW_NAMESPACE}" \
    --values "${PROJECT_ROOT}/helm/airflow-values.yaml" \
    --wait

echo -e "${GREEN}✓ Airflow installed${NC}"
echo ""

# Wait for pods to be ready
echo -e "${YELLOW}Waiting for all pods to be ready...${NC}"
kubectl wait --for=condition=ready pod \
    --namespace "${AIRFLOW_NAMESPACE}" \
    -l "app.kubernetes.io/component=webserver" \
    --timeout=300s

echo -e "${GREEN}✓ All pods ready${NC}"
echo ""

# Print status
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Cluster status:"
kubectl get nodes
echo ""
echo "Airflow pods:"
kubectl get pods -n "${AIRFLOW_NAMESPACE}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Run: ./scripts/port-forward.sh"
echo "  2. Open: http://localhost:8080"
echo ""
echo "To check KEDA ScaledObject:"
echo "  kubectl get scaledobject -n ${AIRFLOW_NAMESPACE}"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/setup.sh
```

- [ ] **Step 3: Verify script**

```bash
ls -la scripts/setup.sh
head -20 scripts/setup.sh
```

Expected: Executable permissions, script content visible

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat: add automated setup script

- Creates Kind cluster
- Installs KEDA Helm chart
- Installs Airflow with CeleryExecutor
- Creates ConfigMap for example DAGs
- Includes prerequisite checks and status output
"
```

---

### Task 6: Create port-forward script

**Files:**
- Create: `scripts/port-forward.sh`

**Purpose:** Simple script to port-forward Airflow webserver to localhost:8080.

- [ ] **Step 1: Create port-forward script**

```bash
#!/usr/bin/env bash
# scripts/port-forward.sh
# Port-forwards Airflow webserver to localhost:8080

set -euo pipefail

NAMESPACE="airflow"
SERVICE="airflow-webserver"
LOCAL_PORT=8080
REMOTE_PORT=8080

echo "Forwarding ${SERVICE}.${NAMESPACE}:${REMOTE_PORT} -> localhost:${LOCAL_PORT}"
echo "Press Ctrl+C to stop"
echo ""
echo "Airflow UI will be available at: http://localhost:${LOCAL_PORT}"
echo "Default credentials: admin / admin"
echo ""

kubectl port-forward \
    -n "${NAMESPACE}" \
    "service/${SERVICE}" \
    "${LOCAL_PORT}:${REMOTE_PORT}"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/port-forward.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/port-forward.sh
git commit -m "feat: add port-forward script for Airflow UI

- Forwards webserver service to localhost:8080
- Includes connection instructions
"
```

---

### Task 7: Create teardown script

**Files:**
- Create: `scripts/teardown.sh`

**Purpose:** Clean script to delete the Kind cluster.

- [ ] **Step 1: Create teardown script**

```bash
#!/usr/bin/env bash
# scripts/teardown.sh
# Deletes the Kind cluster

set -euo pipefail

CLUSTER_NAME="airflow-local"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Deleting cluster: ${CLUSTER_NAME}"
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "Cluster deleted"
else
    echo "No cluster named '${CLUSTER_NAME}' found"
fi
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/teardown.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/teardown.sh
git commit -m "feat: add teardown script

- Deletes Kind cluster
- Checks for cluster existence before deletion
"
```

---

## Chunk 4: Documentation

### Task 8: Create README

**Files:**
- Create: `README.md`

**Purpose:** Complete setup and usage documentation.

- [ ] **Step 1: Create README**

```markdown
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

MIT
```

- [ ] **Step 2: Verify README**

```bash
cat README.md
```

Expected: Documentation displayed

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add comprehensive README

- Quick start guide
- Architecture overview
- KEDA scaling documentation
- Troubleshooting section
"
```

---

## Chunk 5: Verification and Finalization

### Task 9: Final verification

**Purpose:** Ensure all files are in place and scripts are executable.

- [ ] **Step 1: Verify project structure**

```bash
find . -type f -not -path './.git/*' | sort
```

Expected output should include:
- `kind/cluster.yaml`
- `helm/airflow-values.yaml`
- `helm/keda-values.yaml`
- `dags/examples/__init__.py`
- `dags/examples/example_bash_operator.py`
- `dags/examples/example_task_flow.py`
- `scripts/setup.sh`
- `scripts/port-forward.sh`
- `scripts/teardown.sh`
- `README.md`

- [ ] **Step 2: Verify script permissions**

```bash
ls -la scripts/
```

Expected: All `.sh` files should have `-rwxr-xr-x` or similar (executable)

- [ ] **Step 3: Syntax check YAML files**

```bash
# Check if python3 and pyyaml are available
if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    python3 -c "
import yaml
import sys

files = [
    'kind/cluster.yaml',
    'helm/airflow-values.yaml',
    'helm/keda-values.yaml'
]

for f in files:
    try:
        with open(f) as fp:
            yaml.safe_load(fp)
        print(f'✓ {f}')
    except Exception as e:
        print(f'✗ {f}: {e}')
        sys.exit(1)
"
else
    echo "⚠ pyyaml not available, skipping YAML validation"
    echo "Install with: pip install pyyaml"
fi
```

Expected: All files show ✓ (or warning if pyyaml missing)

- [ ] **Step 4: Syntax check Python files**

```bash
python3 -m py_compile dags/examples/*.py
echo "All Python files compiled successfully"
```

Expected: No syntax errors

- [ ] **Step 5: Final commit**

```bash
git status
```

Expected: No uncommitted changes

- [ ] **Step 6: Create summary**

```bash
echo "=== Implementation Plan Complete ==="
echo ""
echo "Files created:"
git ls-tree -r main --name-only
echo ""
echo "Commits:"
git log --oneline
```

---

## Success Criteria

- [ ] All YAML files are valid and syntactically correct
- [ ] All Python DAGs compile without errors
- [ ] All shell scripts are executable
- [ ] Project structure matches the planned layout
- [ ] README provides clear setup instructions
- [ ] Design spec and implementation plan are documented

## Next Steps

After implementation:

1. Run `./scripts/setup.sh` to create the cluster
2. Run `./scripts/port-forward.sh` to access the UI
3. Unpause and trigger example DAGs
4. Verify KEDA scales workers based on queue depth
5. Test teardown with `./scripts/teardown.sh`
