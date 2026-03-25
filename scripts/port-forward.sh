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