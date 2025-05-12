#!/bin/bash
set -e
source ../../global-rc
podman login ${REGISTRY_URL} 
if ! podman pull ${REGISTRY_URL}/${IMAGE_NAME} &>/dev/null; then 
    ulimit -n 65535 && buildah bud -f Dockerfile -t${REGISTRY_URL}/${IMAGE_NAME}
    podman push ${REGISTRY_URL}/${IMAGE_NAME}
else
    echo "`date` Image ${REGISTRY_URL}/${IMAGE_NAME} is already present!"
fi
