#!/usr/bin/env python3
"""Check installed Codex plugin startup without credentials or repository downloads."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time


def probe(executable, disabled):
    with tempfile.TemporaryDirectory(prefix="quotaclock-bandwidth-") as temporary:
        root = Path(temporary)
        # Do not inherit credentials/config. Block Git HTTP traffic at a closed
        # local proxy; GIT_TRACE captures even Codex's absolute-path Git launch.
        environment = {key: value for key, value in os.environ.items()
                       if key in ("TMPDIR", "LANG")}
        environment.update(
            HOME=temporary, CODEX_HOME=temporary, PATH="/usr/bin:/bin",
            HTTPS_PROXY="http://127.0.0.1:9", HTTP_PROXY="http://127.0.0.1:9",
            ALL_PROXY="http://127.0.0.1:9", GIT_TRACE=str(root / "git-attempts"),
        )
        arguments = [executable, "-c", 'cli_auth_credentials_store="file"']
        if disabled:
            arguments += ["-c", "features.plugins=false"]
        process = subprocess.Popen(
            arguments + ["app-server"], cwd=root, env=environment,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True,
        )
        lines = []
        reader = threading.Thread(target=lambda: lines.extend(process.stdout.readlines()), daemon=True)
        reader.start()
        try:
            requests = [
                {"id": 1, "method": "initialize", "params": {
                    "clientInfo": {"name": "QuotaClock", "version": "bandwidth-check"},
                    "capabilities": {"experimentalApi": True}}},
                {"method": "initialized"},
                {"id": 2, "method": "account/read", "params": {"refreshToken": False}},
            ]
            for request in requests:
                process.stdin.write(json.dumps(request) + "\n")
                process.stdin.flush()
            time.sleep(15)
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdin.close()
            reader.join(timeout=2)
        trace = root / "git-attempts"
        replies = [json.loads(line) for line in lines if line.startswith("{")]
        return {
            "case": "plugins-off" if disabled else "baseline",
            "git_attempts": trace.read_text().splitlines() if trace.exists() else [],
            "rpc_reply_ids": [reply.get("id") for reply in replies if "result" in reply],
            "plugin_files": [str(path.relative_to(root)) for path in root.rglob("*")
                             if "plugins" in path.name],
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", help="Path to installed Codex CLI")
    arguments = parser.parse_args()
    results = []
    for disabled in (False, True):
        result = probe(arguments.executable, disabled)
        results.append(result)
        print(json.dumps(result), flush=True)
    assert any("openai/plugins.git" in line for line in results[0]["git_attempts"]), \
        "Baseline did not exercise curated plugin sync"
    assert not results[1]["git_attempts"], "Disabled plugins still launched Git"
    assert not results[1]["plugin_files"], "Disabled plugins still created sync artifacts"
    assert all(1 in result["rpc_reply_ids"] and 2 in result["rpc_reply_ids"] for result in results), \
        "Account RPCs did not succeed"


if __name__ == "__main__":
    main()
