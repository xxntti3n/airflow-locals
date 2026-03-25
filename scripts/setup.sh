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
count=0
until kubectl get crd scaledobjects.keda.sh &>/dev/null; do
  if [ $count -ge 30 ]; then
    echo -e "${RED}Timeout waiting for KEDA CRDs${NC}"
    exit 1
  fi
  sleep 2
  count=$((count + 1))
done
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
