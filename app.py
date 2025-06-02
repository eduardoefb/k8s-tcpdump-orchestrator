from flask import Flask, request, redirect, url_for, render_template_string, send_from_directory
import subprocess
import os
import time

app = Flask(__name__)

TMP_DIR = os.path.abspath("traces")
MONITOR_SCRIPT = "./monitor.sh"
CONFIG_FILE = os.path.abspath("tcpdump_config.txt")
DEFAULT_CONDITION = "-i any -s 0 port 8080"
DEFAULT_TIMEOUT = 300

os.makedirs(TMP_DIR, exist_ok=True)

HTML_BASE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>K8s Tcpdump Orchestrator</title>
  <style>
    :root {
      --bg-color: #f4f4f4;
      --text-color: #333;
      --card-bg: #fff;
      --button-bg: #0d6efd;
      --button-hover: #0b5ed7;
      --pre-bg: #222;
      --pre-color: #0f0;
    }

    body.dark {
      --bg-color: #1e1e1e;
      --text-color: #eee;
      --card-bg: #2c2c2c;
      --button-bg: #5a5aff;
      --button-hover: #4a4aff;
      --pre-bg: #000;
      --pre-color: #0f0;
    }

    body {
      font-family: Arial, sans-serif;
      margin: 2em;
      background-color: var(--bg-color);
      color: var(--text-color);
      transition: background-color 0.3s, color 0.3s;
    }

    h2 { color: var(--button-bg); }

    form {
      margin-bottom: 2em;
      background: var(--card-bg);
      padding: 1em;
      border-radius: 8px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }

    input[type=text], select {
      padding: 0.5em;
      width: 300px;
      margin-bottom: 1em;
      background-color: var(--bg-color);
      color: var(--text-color);
      border: 1px solid #999;
    }

    input[type=submit], button {
      padding: 0.5em 1em;
      background-color: var(--button-bg);
      border: none;
      color: #fff;
      border-radius: 4px;
      cursor: pointer;
    }

    input[type=submit]:hover, button:hover {
      background-color: var(--button-hover);
    }

    pre {
      background-color: var(--pre-bg);
      color: var(--pre-color);
      padding: 1em;
      overflow-x: auto;
      border-radius: 6px;
    }

    ul { padding-left: 1.2em; }

    a {
      color: var(--button-bg);
      text-decoration: none;
    }

    a:hover {
      text-decoration: underline;
    }

    label {
      display: block;
      margin-bottom: 0.5em;
    }

    .toggle-btn {
      float: right;
      margin-top: -2em;
      margin-bottom: 1em;
    }
  </style>
</head>
<body>
<div class="toggle-btn">
  <button onclick="toggleTheme()" id="themeToggleBtn">🌙 Dark Mode</button>
</div>

<h2>K8s Tcpdump Orchestrator</h2>
%s

<script>
  function applyTheme(dark) {
    document.body.classList.toggle("dark", dark);
    const btn = document.getElementById("themeToggleBtn");
    btn.textContent = dark ? "🌞 Light Mode" : "🌙 Dark Mode";
    localStorage.setItem("theme", dark ? "dark" : "light");
  }

  function toggleTheme() {
    const isDark = document.body.classList.contains("dark");
    applyTheme(!isDark);
  }

  const savedTheme = localStorage.getItem("theme");
  if (savedTheme === "dark") applyTheme(true);
</script>

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

<form method="post" action="/set_condition">
  <h3>2. Monitoring condition</h3>
  <input type="text" name="condition" value="{{ condition }}">
  <input type="submit" value="Update">
</form>

<form method="post" action="/set_timeout">
  <h3>3. Monitoring timeout (seconds)</h3>
  <input type="text" name="mon_timeout" value="{{ mon_timeout }}">
  <input type="submit" value="Update">
</form>

<form method="post" action="/status"><input type="submit" value="Check Status"></form>
<form method="post" action="/clear"><input type="submit" value="Clear Files"></form>
<form method="post" action="/stop"><input type="submit" value="Stop and Download All"></form>
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

def get_param(param):
    if not os.path.exists(CONFIG_FILE):
        return None
    with open(CONFIG_FILE, "r") as f:
        for line in f:
            if line.startswith(f"{param}="):
                return line.split("=", 1)[1].strip()
    return None

def set_param(param, value):
    new_line = f"{param}={value}\n"
    if not os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "w") as f:
            f.write(new_line)
    else:
        with open(CONFIG_FILE, "r") as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            if line.startswith(f"{param}="):
                lines[i] = new_line
                break
        else:
            lines.append(new_line)
        with open(CONFIG_FILE, "w") as f:
            f.writelines(lines)

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
    try:
        with open("/var/run/secrets/kubernetes.io/serviceaccount/namespace", "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return default_namespace

def set_default_param():
    if not os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "w") as f:
            f.write(f"condition={DEFAULT_CONDITION}\n")
            f.write(f"timeout={DEFAULT_TIMEOUT}\n")

@app.route("/", methods=["GET", "POST"])
def index():
    set_default_param()
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output="",
        condition=get_param("condition"),
        mon_timeout=get_param("timeout")
    ))

@app.route("/set_condition", methods=["POST"])
def set_condition_route():
    new_condition = request.form['condition']
    set_param("condition", new_condition)
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output=f"condition updated to {new_condition}",
        condition=new_condition,
        mon_timeout=get_param("timeout")
    ))

@app.route("/set_timeout", methods=["POST"])
def set_timeout_route():
    new_timeout = request.form['mon_timeout']
    set_param("timeout", new_timeout)
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output=f"timeout updated to {new_timeout}",
        mon_timeout=new_timeout,
        condition=get_param("condition")
    ))

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
    condition = get_param("condition")
    mon_timeout = get_param("timeout")
    outputs = []
    for pod in selected_pods:
        cmd = f"{MONITOR_SCRIPT} --pod-name {pod} --namespace {namespace} --job-namespace {job_namespace}"
        outputs.append(run_cmd(cmd))
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output="\n".join(outputs),
        condition=condition,
        mon_timeout=mon_timeout
    ))

@app.route("/status", methods=["POST"])
def status():
    output = run_cmd(f"{MONITOR_SCRIPT} --status")
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output=output,
        condition=get_param("condition"),
        mon_timeout=get_param("timeout")
    ))

@app.route("/clear", methods=["POST"])
def clear():
    output = run_cmd(f"{MONITOR_SCRIPT} --clear-files")
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output=output,
        condition=get_param("condition"),
        mon_timeout=get_param("timeout")
    ))

@app.route("/stop", methods=["POST"])
def stop():
    output = run_cmd(f"{MONITOR_SCRIPT} --stop-tcpdump")
    time.sleep(5)
    output += run_cmd(f"{MONITOR_SCRIPT} --get-files")
    return wrap(render_template_string(
        HTML_MENU,
        namespaces=get_namespaces(),
        output=output,
        condition=get_param("condition"),
        mon_timeout=get_param("timeout")
    ))

@app.route("/files")
def list_files():
    files = []
    for root, _, filenames in os.walk(TMP_DIR):
        for name in filenames:
            files.append(os.path.relpath(os.path.join(root, name), TMP_DIR))
    file_list = "<h3>Captured PCAP Files</h3><ul>"
    for f in files:
        file_list += f"<li><a href='/download/%s'>%s</a></li>" % (f, f)
    file_list += "</ul><a href='/'>⬅ Back</a>"
    return wrap(file_list)

@app.route("/download/<path:filename>")
def download(filename):
    return send_from_directory(TMP_DIR, filename, as_attachment=True)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
