"""Exercise an appliance IT through Galaxy's API and its public nginx endpoint.

Uses requests from the pinned Planemo environment. This follows Planemo's
IT serve test rather than treating a long-running service as an output test.
"""
import json
import os
from pathlib import Path
import sys
import time
from urllib.parse import urlsplit, urlunsplit

import requests


def wait_for(check, timeout=180):
    deadline = time.monotonic() + timeout
    while True:
        result = check()
        if result:
            return result
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Timed out waiting for {check.__name__}")
        time.sleep(2)


def main():
    base_url, api_key = sys.argv[1:]
    api = requests.Session()
    api.trust_env = False
    api.headers["x-api-key"] = api_key
    public = requests.Session()
    public.trust_env = False
    report = {}
    history_id = job_id = entry_id = None
    results = Path(os.environ.get("GALAXY_IT_TEST_RESULTS_DIR", "test-results/interactive-tools"))
    results.mkdir(parents=True, exist_ok=True)

    def call(method, path, **kwargs):
        response = api.request(method, f"{base_url}/api/{path}", timeout=30, **kwargs)
        response.raise_for_status()
        return response.json() if response.content else None

    try:
        history_id = call("POST", "histories", json={"name": "Appliance IT smoke"})["id"]
        run = call("POST", "tools", json={
            "tool_id": "appliance_it_http", "history_id": history_id, "inputs": {},
        })
        assert len(run["jobs"]) == 1, run
        job_id = run["jobs"][0]["id"]
        report["job_id"] = job_id

        def active_entry():
            job = call("GET", f"jobs/{job_id}?full=true")
            report["job"] = job
            assert job["state"] not in ("error", "deleted", "ok"), job
            entries = call("GET", f"entry_points?job_id={job_id}")
            assert len(entries) <= 1, entries
            return entries[0] if entries and entries[0]["active"] else None

        entry = wait_for(active_entry)
        entry_id = entry["id"]
        target = call("GET", f"entry_points/{entry_id}/access")["target"]
        parts = urlsplit(target)
        assert parts.hostname and parts.hostname.endswith(".interactivetool.localhost"), target
        assert parts.scheme == "http", target
        # Connect to the published nginx port while preserving Galaxy's generated
        # virtual host. No wildcard DNS or direct access to the IT proxy is used.
        proxy_url = urlunsplit(("http", urlsplit(base_url).netloc, parts.path or "/", parts.query, ""))
        host_header = parts.netloc

        def service_reachable():
            try:
                response = public.get(proxy_url, headers={"Host": host_header}, timeout=5, allow_redirects=False)
                return response.status_code == 200 and response.text == "galaxy-appliance-it-ok\n"
            except requests.RequestException:
                return False

        wait_for(service_reachable, timeout=60)
        report["proxied_response_verified"] = True
        call("DELETE", f"entry_points/{entry_id}")

        def service_stopped():
            job = call("GET", f"jobs/{job_id}?full=true")
            report["job"] = job
            entries = call("GET", f"entry_points?job_id={job_id}")
            removed = all(ep.get("deleted") or not ep.get("target") for ep in entries)
            return job["state"] == "stopped" and removed and not service_reachable()

        wait_for(service_stopped, timeout=60)
        report["stop_verified"] = True
        report["status"] = "success"
        print("Interactive Tool responded through nginx and stopped successfully.")
    except Exception as exc:
        report["status"] = "error"
        report["error"] = str(exc)
        raise
    finally:
        try:
            if job_id and not report.get("stop_verified"):
                call("DELETE", f"jobs/{job_id}")
            if history_id:
                call("DELETE", f"histories/{history_id}")
        finally:
            (results / "service_test_output.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
