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