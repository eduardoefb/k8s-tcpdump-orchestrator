#!/bin/bash
set -e
if [ -f lgobal-rc ]; then 
    source global-rc
fi

export TEMPLATE="templates/job_template.yaml"
export TMP_JOB_YAML="$(mktemp)"
export TMP_DIR="${PWD}/traces"
export MODE=""
export JOB_LIST="jobs.list"


mkdir -p ${TMP_DIR}

usage() {
    echo "Usage:"
    echo "  $0 --pod-name <pod_name> --namespace <pod_namespace> --job-namespace <job_namespace>"
    echo "  $0 --status"
    echo "  $0 --get-files"
    echo "  $0 --stop-tcpdump"
    echo "  $0 --reset"
    exit 1
}

add_to_job_list() {
    grep -q "^${POD_NAME} ${TARGET_NAMESPACE} ${JOB_NAMESPACE}$" "${JOB_LIST}" 2>/dev/null || echo "${POD_NAME} ${TARGET_NAMESPACE} ${JOB_NAMESPACE}" >> "${JOB_LIST}"
}

create_job() {
    echo "[INFO] Fetching node name for pod '${POD_NAME}' in namespace '${TARGET_NAMESPACE}'..."
    NODE_NAME=$(kubectl get pod "${POD_NAME}" -n "${TARGET_NAMESPACE}" -o jsonpath='{.spec.nodeName}')
    JOB_NAME="${POD_NAME}-tcpdump"

    echo "[INFO] Generating Job YAML for Job: ${JOB_NAME} targeting Node: ${NODE_NAME} (in namespace ${JOB_NAMESPACE})"

    POD_NAME="${POD_NAME}" \
    TARGET_NAMESPACE="${TARGET_NAMESPACE}" \
    JOB_NAMESPACE="${JOB_NAMESPACE}" \
    NODE_NAME="${NODE_NAME}" \
    JOB_NAME="${JOB_NAME}" \
    envsubst < "${TEMPLATE}" > "${TMP_JOB_YAML}"

    kubectl apply -n "${JOB_NAMESPACE}" -f "${TMP_JOB_YAML}"
    add_to_job_list
    echo "[INFO] Job '${JOB_NAME}' created and tracked in ${JOB_LIST}."
}

find_job_pod() {
    local pod_name="$1"
    local job_ns="$2"
    kubectl get pods -n "${job_ns}" -l "tcpdump-target-pod=${pod_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

check_all_status() {
    if [[ ! -f "${JOB_LIST}" ]]; then
        echo "No jobs found in ${JOB_LIST}"
        exit 0
    fi

    echo "[INFO] Checking status of all tracked jobs..."
    while read -r POD_NAME TARGET_NAMESPACE JOB_NAMESPACE; do
        POD=$(find_job_pod "${POD_NAME}" "${JOB_NAMESPACE}")
        if [[ -z "${POD}" ]]; then
            echo "${POD_NAME} (${TARGET_NAMESPACE}): Job pod not found in ${JOB_NAMESPACE}"
            continue
        fi

        if kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- test -f /tmp/tcpdump_running 2>/dev/null; then
            echo "${POD_NAME} (${TARGET_NAMESPACE}): Tcpdump is running"
        elif kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- test -f /tmp/job_running 2>/dev/null; then
            echo "${POD_NAME} (${TARGET_NAMESPACE}): Tcpdump finished"
        else
            echo "${POD_NAME} (${TARGET_NAMESPACE}): No job detected"
        fi
    done < "${JOB_LIST}"
}

stop_all_tcpdumps() {
    if [[ ! -f "${JOB_LIST}" ]]; then
        echo "No jobs found in ${JOB_LIST}"
        exit 0
    fi

    echo "[INFO] Stopping all running tcpdump jobs..."
    while read -r POD_NAME TARGET_NAMESPACE JOB_NAMESPACE; do
        POD=$(find_job_pod "${POD_NAME}" "${JOB_NAMESPACE}")
        [[ -z "${POD}" ]] && continue
        echo "-> ${POD_NAME} (${TARGET_NAMESPACE})"
        kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- rm -f /tmp/tcpdump_running || true
    done < "${JOB_LIST}"
    echo "[INFO] All tcpdumps stopped."
}

get_all_files() {
    if [[ ! -f "${JOB_LIST}" ]]; then
        echo "No jobs found in ${JOB_LIST}"
        exit 0
    fi

    if [ ! -d ${TMP_DIR} ]; then
        TMP_DIR=$(mktemp -d)
    fi 
    
    echo "[INFO] Downloading pcap files to: ${TMP_DIR}"

    while read -r POD_NAME TARGET_NAMESPACE JOB_NAMESPACE; do
        POD=$(find_job_pod "${POD_NAME}" "${JOB_NAMESPACE}")
        [[ -z "${POD}" ]] && continue

        echo "-> ${POD_NAME} (${TARGET_NAMESPACE})"

        if kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- test ! -f /tmp/tcpdump_running && \
           kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- test -f /tmp/job_running; then
            LOCAL_DIR="${TMP_DIR}/${POD_NAME}_${TARGET_NAMESPACE}_pcap"
            mkdir -p "${LOCAL_DIR}"
            kubectl cp "${JOB_NAMESPACE}/${POD}:/tmp/pcap" "${LOCAL_DIR}" || echo "Failed to copy pcap"
            kubectl exec -n "${JOB_NAMESPACE}" "${POD}" -- rm -f /tmp/job_running || true
        else
            echo "   [!] Skipped: Tcpdump still running or no job"
        fi
    done < "${JOB_LIST}"
    
    echo "[INFO] All files collected in ${TMP_DIR}"
    reset_job_list

    echo "[INFO] Merging all .pcap files into ${TMP_DIR}/merged_all.pcap"
    PCAP_LIST=$(find "${TMP_DIR}" -type f -name '*.pcap')
    if [[ -n "${PCAP_LIST}" ]]; then
        mergecap -w "${TMP_DIR}/merged_all.pcap" ${PCAP_LIST}
        echo "[INFO] Merged file created: ${TMP_DIR}/merged_all.pcap"
    else
        echo "[WARN] No .pcap files found to merge."
    fi
}

reset_job_list() {
    rm -f "${JOB_LIST}"
    echo "[INFO] Job list cleared: ${JOB_LIST}"
}

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --pod-name) POD_NAME="$2"; shift ;;
        --namespace) TARGET_NAMESPACE="$2"; shift ;;
        --job-namespace) JOB_NAMESPACE="$2"; shift ;;
        --status) MODE="status" ;;
        --get-files) MODE="getpcap" ;;
        --stop-tcpdump) MODE="stop" ;;
        --reset) MODE="reset" ;;
        *) usage ;;
    esac
    shift
done

# Execution logic
if [[ -n "${POD_NAME}" && -n "${TARGET_NAMESPACE}" && -n "${JOB_NAMESPACE}" ]]; then
    create_job
elif [[ "${MODE}" == "status" ]]; then
    check_all_status
elif [[ "${MODE}" == "getpcap" ]]; then
    get_all_files    
elif [[ "${MODE}" == "stop" ]]; then
    stop_all_tcpdumps
elif [[ "${MODE}" == "reset" ]]; then
    reset_job_list
else
    usage
fi
