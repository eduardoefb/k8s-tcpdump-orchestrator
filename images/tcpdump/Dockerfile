FROM debian:12

LABEL maintainer="eduardoefb@gmail.com"

# Set noninteractive frontend to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive \
    VERSION="v1.32.0"
    
RUN  DEBIAN_FRONTEND=noninteractive apt-get update && \
     DEBIAN_FRONTEND=noninteractive apt-get -y install tcpdump iproute2 wget jq curl procps
    
RUN  wget https://github.com/kubernetes-sigs/cri-tools/releases/download/${VERSION}/crictl-${VERSION}-linux-amd64.tar.gz &&\
     tar zxvf crictl-${VERSION}-linux-amd64.tar.gz -C /usr/local/bin && \
     rm -f crictl-${VERSION}-linux-amd64.tar.gz

RUN  DEBIAN_FRONTEND=noninteractive apt-get -y remove wget && \
     DEBIAN_FRONTEND=noninteractive apt-get -y purge wget && \
     rm -rf /var/lib/apt/lists/*

COPY exec.sh /opt/exec.sh 
RUN chmod +x /opt/exec.sh
     


