FROM python:3.11-slim

WORKDIR /app
RUN mkdir /app/templates/

COPY app.py /app/app.py
COPY monitor.sh /app/monitor.sh
COPY job_template.yaml /app/templates/job_template.yaml

RUN apt-get update && apt-get install -y curl iputils-ping procps gettext wireshark-common \
    && pip install --no-cache-dir flask 

RUN mkdir /opt/templates

RUN cd /tmp/ && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    mv /tmp/kubectl /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl


EXPOSE 5000

CMD ["python", "app.py"]
