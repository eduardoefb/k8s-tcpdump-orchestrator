#!/bin/bash

set -e

usage() {
  echo "Usage: $0 {create|destroy}"
  exit 1
}

build() {
    CWD=${PWD}
    echo $HARBOR_PASS | podman login ${HARBOR_URL} --username $HARBOR_USER --password-stdin
    podman login ${HARBOR_URL} 
    cd images/tcpdump
    bash create_image.sh
    cd ${CWD}
    cd images/orchestrator
    bash create_image.sh
    cd ${CWD}
}

create() {
    build
    CWD=${PWD}
    cd helm
    helm package ${HELM_CHART_NAME}
    set +e
    helm repo remove ${HARBOR_PROJECT} &>/dev/null
    set -e
    helm repo add  --username ${HARBOR_USER} --password ${HARBOR_PASS} ${HARBOR_PROJECT} https://${HARBOR_URL}/chartrepo/${HARBOR_PROJECT}
    helm cm-push ${HELM_CHART_NAME}-${HELM_VERSION}.tgz ${HARBOR_PROJECT}
    helm repo update
    if [ -f *.tgz ]; then
        rm *.tgz
    fi
    cd ${CWD}

    cd terraform
    tofu init
    tofu apply --auto-approve
    cd ${CWD}
}

destroy() {
    CWD=${PWD}
    cd terraform   
    tofu init 
    tofu destroy --auto-approve
    cd ${CWD}
}

export HARBOR_PROJECT="tcpdump"
export HARBOR_USER="tcpdump"
export HARBOR_PASS=`curl -k --header "X-Vault-Token: ${VAULT_TOKEN}" https://${VAULT_URL}/v1/secret/data/harbor-credentials | jq -r '.data.data.users[] | select(.user == "'${HARBOR_USER}'") | .password'`
export HELM_CHART_NAME="orchestrator"
export HELM_VERSION="0.1.0"
export ISTIO_LB_IP=`kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
export TF_VAR_k8s_domain="k8slab.int"
export TF_VAR_namespace="tcpdump"
export TF_VAR_harbor_user=${HARBOR_USER}
export TF_VAR_harbor_pass=${HARBOR_PASS}
export TF_VAR_helm_chart_name=${HELM_CHART_NAME}
export TF_VAR_helm_version=${HELM_VERSION}
export TF_VAR_istio_lb_ip=${ISTIO_LB_IP}
export TF_VAR_orchestration_installation_name="orc8r"
export TF_VAR_harbor_project=${HARBOR_PROJECT}



case "$1" in
  create)
    create
    ;;
  destroy)
    destroy
    ;;
  *)
    usage
    ;;
esac


