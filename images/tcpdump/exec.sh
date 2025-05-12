#!/bin/bash

set -e
RUNNING_JOB="/tmp/job_running"
RUNNING_TCPDUMP="/tmp/tcpdump_running"


touch ${RUNNING_JOB}
touch ${RUNNING_TCPDUMP}

TCPDUMP_COMMAND="tcpdump ${CONDITION}"

pod_id=`crictl pods --name ${POD_NAME} --namespace ${NAMESPACE} --state Ready -o json | jq -r '.items[0].id'`
mapfile -t container_ids < <(crictl ps -p "${pod_id}" -o json | jq -r '.containers[].id')
mapfile -t container_names < <(crictl ps -p "${pod_id}" -o json | jq -r '.containers[].metadata.name')

mkdir /tmp/pcap
for i in ${!container_ids[@]}; do
   container_pid=`crictl inspect ${container_ids[i]} | jq -r .info.pid`
   random_string=`openssl rand -hex 2`
   timestamp=`date +'%Y%m%d%H%M%S'`
   echo ${container_names[i]}
   nohup nice timeout ${TIMEOUT} nsenter --target ${container_pid} --net -- ${TCPDUMP_COMMAND} -w /tmp/pcap/${timestamp}-${random_string}-${POD_NAME}-${container_names[i]}.pcap >/dev/null 2>&1&
done


while true; do
   if [ ! -f ${RUNNING_TCPDUMP} ]; then 
      break
   fi 
   echo "[INFO] $(date) ${RUNNING_TCPDUMP} present.  Waiting."
   sleep 2
done

# Kill tcpdump:
ps aux | grep 'nsenter.*tcpdump' | grep -v grep | awk '{print $2}' | xargs -r kill -9


# Wait until files are not yet downloaded
while true; do
   if [ ! -f ${RUNNING_JOB} ]; then 
      break
   fi 
   echo "[INFO] $(date) ${RUNNING_JOB} present.  Waiting."
   sleep 2
done


