#!/usr/bin/env python3
"""Local-only web control panel for vpnkit diagnostic scripts.

This intentionally exposes only a small fixed set of repo scripts and validates
arguments before spawning subprocesses. It is designed for operator-local use;
default bind address is 127.0.0.1.
"""
from __future__ import annotations

import argparse
import html
import os
import re
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
MAX_OUTPUT_CHARS = 120_000
IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
REMOTE_RE = re.compile(r"([A-Za-z0-9._-]+):1194")
SAFE_HOST_RE = re.compile(r"^[A-Za-z0-9_.@:-]+$")
SAFE_SLOTS_RE = re.compile(r"^[1-5](?:[ ,]+[1-5])*$")

jobs: dict[str, dict[str, object]] = {}
jobs_lock = threading.Lock()
FORM_TOKEN = uuid.uuid4().hex


def default_router_host() -> str:
    env_host = os.environ.get("ASUS_SSH_HOST") or os.environ.get("VPNKIT_ASUS_SSH_HOST")
    if env_host:
        return env_host
    try:
        out = subprocess.check_output(["ip", "route", "show", "default"], text=True, timeout=2)
        parts = out.split()
        if "via" in parts:
            gw = parts[parts.index("via") + 1]
            return f"admin@{gw}"
    except Exception:
        pass
    return "admin@router.local"


def default_key_path() -> str:
    env_key = os.environ.get("ASUS_SSH_KEY") or os.environ.get("VPNKIT_ASUS_SSH_KEY")
    if env_key:
        return env_key
    candidate = Path.home() / ".ssh" / "asus-rt-ax56u"
    return str(candidate) if candidate.exists() else ""


def redact(text: str) -> str:
    text = IP_RE.sub("<IP>", text)
    text = REMOTE_RE.sub("<remote>:1194", text)
    return text


def add_job(label: str, cmd: list[str], env: dict[str, str] | None = None) -> str:
    job_id = uuid.uuid4().hex[:10]
    record: dict[str, object] = {
        "id": job_id,
        "label": label,
        "status": "running",
        "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ended": "",
        "returncode": None,
        "output": "",
    }
    with jobs_lock:
        jobs[job_id] = record

    def runner() -> None:
        proc_env = os.environ.copy()
        if env:
            proc_env.update(env)
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=str(REPO_ROOT),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=proc_env,
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                with jobs_lock:
                    out = str(record["output"]) + redact(line)
                    if len(out) > MAX_OUTPUT_CHARS:
                        out = out[-MAX_OUTPUT_CHARS:]
                        out = "[output truncated to latest lines]\n" + out
                    record["output"] = out
            rc = proc.wait()
            with jobs_lock:
                record["status"] = "done" if rc == 0 else "failed"
                record["returncode"] = rc
                record["ended"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        except Exception as exc:  # noqa: BLE001 - report locally to operator
            with jobs_lock:
                record["status"] = "failed"
                record["returncode"] = -1
                record["ended"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                record["output"] = str(record["output"]) + redact(f"launcher_error={exc}\n")

    threading.Thread(target=runner, daemon=True).start()
    return job_id


def page(title: str, body: str, refresh: bool = False) -> bytes:
    refresh_tag = '<meta http-equiv="refresh" content="2">' if refresh else ""
    doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  {refresh_tag}
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 980px; margin: 24px auto; padding: 0 16px; background: #101418; color: #eef2f6; }}
    a {{ color: #8ecbff; }}
    .card {{ background: #171d23; border: 1px solid #2a343f; border-radius: 12px; padding: 16px; margin: 16px 0; }}
    label {{ display: block; margin-top: 10px; font-weight: 600; }}
    input {{ width: 100%; box-sizing: border-box; padding: 8px; border-radius: 8px; border: 1px solid #45515e; background: #0d1117; color: #eef2f6; }}
    button {{ margin-top: 14px; padding: 9px 14px; border-radius: 8px; border: 0; background: #2f81f7; color: white; font-weight: 700; cursor: pointer; }}
    .danger button {{ background: #da3633; }}
    .warn {{ color: #ffd166; }}
    pre {{ white-space: pre-wrap; word-break: break-word; background: #05070a; border: 1px solid #2a343f; padding: 12px; border-radius: 10px; }}
    .muted {{ color: #a8b3bd; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  {body}
</body>
</html>"""
    return doc.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:
        # Avoid logging query/path values that may contain private host aliases.
        print(f"{self.address_string()} - {fmt % args}")

    def send_html(self, body: bytes, code: int = 200) -> None:
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/":
            self.send_html(page("VPN diagnostics control panel", self.index_body()))
            return
        if path.startswith("/jobs/"):
            job_id = path.rsplit("/", 1)[-1]
            with jobs_lock:
                job = dict(jobs.get(job_id, {}))
            if not job:
                self.send_html(page("Job not found", "<p>Unknown job.</p><p><a href='/'>Back</a></p>"), 404)
                return
            refresh = job.get("status") == "running"
            body = f"""
<p><a href='/'>← Back</a></p>
<div class='card'>
  <p><b>Job:</b> {html.escape(str(job.get('label', '')))}</p>
  <p><b>Status:</b> {html.escape(str(job.get('status', '')))} | <b>Return code:</b> {html.escape(str(job.get('returncode', '')))}</p>
  <p class='muted'>Started: {html.escape(str(job.get('started', '')))} Ended: {html.escape(str(job.get('ended', '')))}</p>
</div>
<pre>{html.escape(str(job.get('output', '')))}</pre>
"""
            self.send_html(page("VPN diagnostics job", body, refresh=refresh))
            return
        self.send_html(page("Not found", "<p>Not found.</p>"), 404)

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        data = parse_qs(self.rfile.read(length).decode("utf-8", errors="replace"))
        path = urlparse(self.path).path
        try:
            if path == "/run/profile-check":
                job_id = self.start_profile_check(data)
            elif path == "/run/asus-cycle":
                job_id = self.start_asus_cycle(data)
            else:
                self.send_html(page("Not found", "<p>Not found.</p>"), 404)
                return
        except ValueError as exc:
            self.send_html(page("Input rejected", f"<p>{html.escape(str(exc))}</p><p><a href='/'>Back</a></p>"), 400)
            return
        self.send_response(303)
        self.send_header("Location", f"/jobs/{job_id}")
        self.end_headers()

    def field(self, data: dict[str, list[str]], name: str) -> str:
        return data.get(name, [""])[0].strip()

    def start_profile_check(self, data: dict[str, list[str]]) -> str:
        profile = self.field(data, "profile")
        if not profile:
            raise ValueError("Profile path is required.")
        profile_path = Path(profile).expanduser()
        if not profile_path.is_absolute():
            raise ValueError("Profile path must be absolute.")
        if profile_path.suffix != ".ovpn" or not profile_path.is_file():
            raise ValueError("Profile must be a readable .ovpn file.")
        cmd = [str(REPO_ROOT / "scripts" / "vpnkit-profile-check.sh"), str(profile_path)]
        return add_job(f"profile-check {profile_path.name}", cmd)

    def start_asus_cycle(self, data: dict[str, list[str]]) -> str:
        token = self.field(data, "token")
        if token != FORM_TOKEN:
            raise ValueError("Stale or invalid form token. Reload the page and try again.")
        host = self.field(data, "host")
        port = self.field(data, "port") or "707"
        key = self.field(data, "key")
        slots = self.field(data, "slots")
        wait = self.field(data, "wait") or "60"
        if not host or not SAFE_HOST_RE.match(host):
            raise ValueError("SSH host is required and may contain only safe host characters.")
        if not port.isdigit() or not wait.isdigit():
            raise ValueError("Port and wait seconds must be numeric.")
        if not SAFE_SLOTS_RE.match(slots):
            raise ValueError("Slots must be 1..5 separated by commas or spaces.")
        cmd = [
            str(REPO_ROOT / "scripts" / "openvpn-asus-client-cycle-test.sh"),
            "--host", host,
            "--port", port,
            "--slots", slots,
            "--wait-seconds", wait,
            "--yes",
        ]
        if key:
            key_path = Path(key).expanduser()
            if not key_path.is_absolute() or not key_path.is_file():
                raise ValueError("SSH key must be an absolute readable file path when provided.")
            cmd.extend(["--key", str(key_path)])
        return add_job("asus-client-cycle", cmd, env={"ASUS_CONFIRM": "YES"})

    def index_body(self) -> str:
        recent = []
        with jobs_lock:
            for job_id, job in list(jobs.items())[-10:]:
                recent.append(
                    f"<li><a href='/jobs/{job_id}'>{html.escape(str(job.get('label', 'job')))}</a> "
                    f"— {html.escape(str(job.get('status', '')))}</li>"
                )
        recent_html = "<ul>" + "".join(recent) + "</ul>" if recent else "<p class='muted'>No jobs yet.</p>"
        router_host = html.escape(default_router_host(), quote=True)
        key_path = html.escape(default_key_path(), quote=True)
        token = html.escape(FORM_TOKEN, quote=True)
        return f"""
<p class='warn'><b>Local-only tool.</b> Bind address defaults to 127.0.0.1. Output is redacted for IPv4 addresses/endpoints, but do not paste secrets into fields.</p>
<div class='card'>
  <h2>OpenVPN profile check in throwaway Docker client</h2>
  <form method='post' action='/run/profile-check'>
    <label>Absolute .ovpn profile path</label>
    <input name='profile' placeholder='/home/user/profile.ovpn' required>
    <button type='submit'>Run profile check</button>
  </form>
</div>
<div class='card danger'>
  <h2>ASUS router client slot cycle test</h2>
  <p class='warn'><b>Danger:</b> this SSHes to the router, starts/stops VPN client slots, and can temporarily break Internet for this computer. The script traps exit and stops tested slots, but use only with a recovery path.</p>
  <form method='post' action='/run/asus-cycle'>
    <input type='hidden' name='token' value='{token}'>
    <label>SSH host</label>
    <input name='host' value='{router_host}' required>
    <label>SSH port</label>
    <input name='port' value='707'>
    <label>SSH private key path (optional)</label>
    <input name='key' value='{key_path}'>
    <label>Slots, 1..5</label>
    <input name='slots' value='1,2,3,4' required>
    <label>Wait seconds per slot</label>
    <input name='wait' value='60'>
    <button type='submit'>Run router cycle test</button>
  </form>
</div>
<div class='card'>
  <h2>Recent jobs</h2>
  {recent_html}
</div>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Local-only vpnkit diagnostics web control panel")
    parser.add_argument("--host", default=DEFAULT_HOST, help="bind host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="bind port (default: 8765)")
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        print("Refusing non-local bind without VPNKIT_CONTROL_PANEL_ALLOW_NONLOCAL=YES", flush=True)
        if os.environ.get("VPNKIT_CONTROL_PANEL_ALLOW_NONLOCAL") != "YES":
            return 2
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"VPN diagnostics control panel: http://{args.host}:{args.port}/", flush=True)
    print("Press Ctrl+C to stop.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
