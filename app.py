from flask import Flask, request, redirect, url_for, render_template_string, send_from_directory
import subprocess
import os
import tempfile
import threading
import time

app = Flask(__name__)

TMP_DIR = os.path.abspath("traces")
MONITOR_SCRIPT = "./monitor.sh"

os.makedirs(TMP_DIR, exist_ok=True)

tcpdump_running = False

HTML_BASE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>K8s Tcpdump Orchestrator</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 2em; background-color: #f4f4f4; color: #333; }
    h2 { color: #0d6efd; }
    form { margin-bottom: 2em; background: #fff; padding: 1em; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    input[type=text], select { padding: 0.5em; width: 300px; margin-bottom: 1em; }
    input[type=submit] { padding: 0.5em 1em; background-color: #0d6efd; border: none; color: #fff; border-radius: 4px; cursor: pointer; }
    input[type=submit]:hover { background-color: #0b5ed7; }
    pre { background-color: #222; color: #0f0; padding: 1em; overflow-x: auto; border-radius: 6px; }
    ul { padding-left: 1.2em; }
    a { color: #0d6efd; text-decoration: none; }
    a:hover { text-decoration: underline; }
    label { display: block; margin-bottom: 0.5em; }
  </style>
</head>
<body>
<h2>K8s Tcpdump Orchestrator</h2>
%s
</body>
</html>
"""

HTML_MENU = """
<form method="post" action="/start">
  <h3>1. Choose namespace</h3>
  <select name="namespace">
    {% for ns in namespaces %}
      <option value="{{ ns }}">{{ ns }}</option>
    {% endfor %}
  </select>
  <input type="submit" value="List Pods">
</form>
<form method="post" action="/status">
  <input type="submit" value="Check Status">
</form>
<form method="post" action="/stop">
  <input type="submit" value="Stop and Download All">
</form>
<a href="/files">📂 View Captured PCAP Files</a>
<pre>{{output}}</pre>
"""

HTML_POD_SELECTION = """
<h3>Select pods in namespace: {{ namespace }}</h3>
<form method="post" action="/launch">
  {% for pod in pods %}
    <label><input type="checkbox" name="pod" value="{{ pod }}"> {{ pod }}</label>
  {% endfor %}
  <input type="hidden" name="namespace" value="{{ namespace }}">
  <input type="submit" value="Start Tcpdump on Selected Pods">
</form>
<a href="/">⬅ Back</a>
"""

def wrap(content):
    return render_template_string(HTML_BASE % content)

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, text=True, check=True, capture_output=True)
        return result.stdout + result.stderr
    except subprocess.CalledProcessError as e:
        return f"Error: {e.stderr or str(e)}"

def get_namespaces():
    result = subprocess.run("kubectl get ns -o jsonpath='{.items[*].metadata.name}'", shell=True, capture_output=True, text=True)
    return sorted(result.stdout.strip("'").split())

def get_pods(namespace):
    result = subprocess.run(f"kubectl get pods -n {namespace} -o jsonpath='{{.items[*].metadata.name}}'", shell=True, capture_output=True, text=True)
    return sorted(result.stdout.strip("'").split())

def get_job_namespace(default_namespace="default"):
    path = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return default_namespace


@app.route("/", methods=["GET", "POST"])
def index():
    return wrap(render_template_string(HTML_MENU, namespaces=get_namespaces(), output=""))

@app.route("/start", methods=["POST"])
def list_pods():
    ns = request.form['namespace']
    pods = get_pods(ns)
    return wrap(render_template_string(HTML_POD_SELECTION, namespace=ns, pods=pods))

@app.route("/launch", methods=["POST"])
def launch_jobs():
    namespace = request.form['namespace']
    job_namespace = get_job_namespace()    
    selected_pods = request.form.getlist('pod')
    outputs = []
    for pod in selected_pods:
        cmd = f"{MONITOR_SCRIPT} --pod-name {pod} --namespace {namespace} --job-namespace {job_namespace}"
        outputs.append(run_cmd(cmd))
    return wrap(render_template_string(HTML_MENU, namespaces=get_namespaces(), output="\n".join(outputs)))

@app.route("/status", methods=["POST"])
def status():
    output = run_cmd(f"{MONITOR_SCRIPT} --status")
    return wrap(render_template_string(HTML_MENU, namespaces=get_namespaces(), output=output))

@app.route("/stop", methods=["POST"])
def stop():
    global tcpdump_running
    tcpdump_running = False
    output = run_cmd(f"{MONITOR_SCRIPT} --stop-tcpdump")
    time.sleep(5)
    output += run_cmd(f"{MONITOR_SCRIPT} --get-files")
    return wrap(render_template_string(HTML_MENU, namespaces=get_namespaces(), output=output))

@app.route("/files")
def list_files():
    files = []
    for root, _, filenames in os.walk(TMP_DIR):
        for name in filenames:
            files.append(os.path.relpath(os.path.join(root, name), TMP_DIR))
    file_list = "<h3>Captured PCAP Files</h3><ul>"
    for f in files:
        file_list += f"<li><a href='/download/{f}'>{f}</a></li>"
    file_list += "</ul><a href='/'>⬅ Back</a>"
    return wrap(file_list)

@app.route("/download/<path:filename>")
def download(filename):
    return send_from_directory(TMP_DIR, filename, as_attachment=True)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
