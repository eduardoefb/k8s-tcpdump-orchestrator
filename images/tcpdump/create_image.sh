#!/bin/bash
set -euo pipefail

source ../../global-rc

# Validate required variables
if [[ -z "${REGISTRY_URL:-}" || -z "${TCPDUMP_IMAGE_NAME:-}" ]]; then
    echo "[ERROR] REGISTRY_URL or IMAGE_NAME not set. Check your global-rc file."
    exit 1
fi

# Login to registry
echo "[INFO] Logging in to registry: ${REGISTRY_URL}"
podman login "${REGISTRY_URL}"

# Check if image already exists in registry
if podman pull "${REGISTRY_URL}/${TCPDUMP_IMAGE_NAME}" &>/dev/null; then
    echo "[INFO] Image ${REGISTRY_URL}/${TCPDUMP_IMAGE_NAME} already exists. Skipping build."
else
    echo "[INFO] Building image: ${REGISTRY_URL}/${TCPDUMP_IMAGE_NAME}"
    ulimit -n 65535
    buildah bud -f Dockerfile -t "${REGISTRY_URL}/${TCPDUMP_IMAGE_NAME}"

    echo "[INFO] Pushing image to registry..."
    podman push "${REGISTRY_URL}/${TCPDUMP_IMAGE_NAME}"
    echo "[INFO] Image pushed successfully."
fi
