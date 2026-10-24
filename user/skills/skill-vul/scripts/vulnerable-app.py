"""故意不安全的静态扫描靶标；不应部署到真实环境。"""
import base64
import hashlib
import os
from pathlib import Path
import pickle
import sqlite3
import subprocess

from flask import Flask, request, render_template_string
import requests
import yaml


app = Flask(__name__)
# SRC-09: 虚构的硬编码凭据，没有真实服务对应。
app.secret_key = "skill-vul-demo-session-signing-key"
ADMIN_PASSWORD = "demo-admin-password-123"
ROOT = Path(__file__).resolve().parents[1]


@app.get("/users")
def users():
    # SRC-01 CWE-89：HTTP 参数直接拼接 SQL。
    name = request.args.get("name", "alice")
    with sqlite3.connect(":memory:") as db:
        db.execute("CREATE TABLE users (name TEXT, note TEXT)")
        db.executemany("INSERT INTO users VALUES (?, ?)",
                       [("alice", "demo user"), ("admin", "fixture only")])
        return {"rows": db.execute("SELECT * FROM users WHERE name = '" + name + "'").fetchall()}


@app.get("/diagnose")
def diagnose():
    # SRC-02 CWE-78：未校验参数进入 shell。
    host = request.args.get("host", "127.0.0.1")
    return subprocess.check_output("ping -c 1 " + host, shell=True, text=True, timeout=5)


@app.get("/file")
def read_file():
    # SRC-03 CWE-22：没有规范化或验证路径是否仍位于 fixtures。
    filename = request.args.get("name", "demo-credentials.json")
    return (ROOT / "fixtures" / filename).read_text()


@app.get("/fetch")
def fetch_url():
    # SRC-04 CWE-918 / SRC-10 CWE-295：任意 URL + 禁用 TLS 校验。
    url = request.args.get("url", "https://service.invalid/status")
    return requests.get(url, verify=False, timeout=5).text


@app.get("/hello")
def hello():
    # SRC-05 CWE-79：不可信文本进入 HTML，未转义。
    return "<h1>Hello " + request.args.get("name", "visitor") + "</h1>"


@app.post("/render")
def render():
    # SRC-06 CWE-1336：用户提交完整模板，服务端直接解释。
    return render_template_string(request.get_data(as_text=True))


@app.post("/restore")
def restore():
    # SRC-07 CWE-502：HTTP 输入经 base64 解码后直接反序列化。
    return {"result": str(pickle.loads(base64.b64decode(request.get_data())))}


@app.post("/import-yaml")
def import_yaml():
    # SRC-08 / DEP-01：PyYAML 5.3.1 的 FullLoader 处理不可信数据。
    return {"result": str(yaml.load(request.get_data(as_text=True), Loader=yaml.FullLoader))}


@app.post("/password-digest")
def password_digest():
    # SRC-11 CWE-759/CWE-328：密码使用无盐 MD5。
    return {"digest": hashlib.md5(request.form.get("password", "").encode()).hexdigest()}


if __name__ == "__main__":
    if os.environ.get("SKILL_VUL_LAB") != "1":
        raise SystemExit("仅供扫描；实验室显式设置 SKILL_VUL_LAB=1 后才可启动。")
    app.run(host="127.0.0.1", port=8765, debug=False)
