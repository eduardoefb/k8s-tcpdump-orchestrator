#!/bin/bash
set -euo pipefail
source ../../global-rc

: "${REGISTRY_URL:?REGISTRY_URL not set}"
: "${ORCHESTRATOR_IMAGE_NAME:?IMAGE_NAME not set}"

podman login "${REGISTRY_URL}"

cp ../../monitor.sh .
cp ../../app.py .
cp ../../templates/job_template.yaml .

if podman pull "${REGISTRY_URL}/${ORCHESTRATOR_IMAGE_NAME}" &>/dev/null; then
    echo "$(date) - Image ${REGISTRY_URL}/${ORCHESTRATOR_IMAGE_NAME} already exists."
else
    echo "$(date) - Building image ${ORCHESTRATOR_IMAGE_NAME}..."
    ulimit -n 65535
    buildah bud -f Dockerfile -t "${REGISTRY_URL}/${ORCHESTRATOR_IMAGE_NAME}" .
    podman push "${REGISTRY_URL}/${ORCHESTRATOR_IMAGE_NAME}"
fi

rm monitor.sh
rm app.py
rm job_template.yaml
