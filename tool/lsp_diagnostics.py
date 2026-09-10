#!/usr/bin/env python3
"""Dump every GDScript analyzer diagnostic the Godot editor would show.

Why this exists
---------------
GDScript *analyzer* warnings (shadowed variables, integer division, unused
signals, unreachable code, ...) are produced by the editor's script analyzer.
They are never printed by ``godot --import``, ``godot --check-only`` or a
headless ``--script`` run, so a project can look perfectly clean in CI while the
editor's debugger panel lists dozens of diagnostics.

The editor exposes exactly those diagnostics over its built-in Language Server
(``textDocument/publishDiagnostics``). This tool speaks just enough LSP to open
every ``.gd`` file in the project and print what the analyzer reports for it,
one ``path:line:col: severity: message`` per line, so the diagnostics can be
triaged from a terminal or from CI.

Usage:
    godot --headless --editor --path . &      # starts the LSP on :6005
    python3 tool/lsp_diagnostics.py --root .  # prints the diagnostics
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time

SEVERITY = {1: "ERROR", 2: "WARNING", 3: "INFO", 4: "HINT"}


class LspClient:
    """Minimal blocking LSP client over a TCP socket."""

    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buf = b""
        self.next_id = 1

    def send(self, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)

    def request(self, method: str, params: dict) -> None:
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        self.next_id += 1

    def notify(self, method: str, params: dict) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def _read_message(self, timeout: float):
        self.sock.settimeout(timeout)
        while True:
            header_end = self.buf.find(b"\r\n\r\n")
            if header_end != -1:
                header = self.buf[:header_end].decode("utf-8", "replace")
                length = 0
                for line in header.split("\r\n"):
                    if line.lower().startswith("content-length:"):
                        length = int(line.split(":", 1)[1].strip())
                body_start = header_end + 4
                while len(self.buf) < body_start + length:
                    chunk = self.sock.recv(65536)
                    if not chunk:
                        return None
                    self.buf += chunk
                body = self.buf[body_start:body_start + length]
                self.buf = self.buf[body_start + length:]
                try:
                    return json.loads(body.decode("utf-8", "replace"))
                except json.JSONDecodeError:
                    continue
            chunk = self.sock.recv(65536)
            if not chunk:
                return None
            self.buf += chunk

    def drain(self, seconds: float, sink) -> None:
        """Read messages until `seconds` of silence, handing each to sink()."""
        deadline = time.time() + seconds
        quiet_deadline = time.time() + seconds
        while time.time() < deadline:
            remaining = min(2.0, max(0.05, quiet_deadline - time.time()))
            try:
                msg = self._read_message(remaining)
            except socket.timeout:
                continue
            except OSError:
                return
            if msg is None:
                return
            quiet_deadline = time.time() + seconds
            sink(msg)


def collect(root: str, host: str, port: int, wait: float) -> list[str]:
    root_abs = os.path.abspath(root)
    files = []
    for dirpath, dirnames, filenames in os.walk(root_abs):
        dirnames[:] = [d for d in dirnames if d not in {".git", ".godot", "node_modules"}]
        for name in sorted(filenames):
            if name.endswith(".gd"):
                files.append(os.path.join(dirpath, name))
    files.sort()

    sock = socket.create_connection((host, port), timeout=30)
    client = LspClient(sock)
    lines: list[str] = []
    seen: set[str] = set()

    def sink(msg: dict) -> None:
        if msg.get("method") != "textDocument/publishDiagnostics":
            return
        params = msg.get("params", {})
        uri = params.get("uri", "")
        path = uri.replace("file://", "")
        for d in params.get("diagnostics", []):
            start = d.get("range", {}).get("start", {})
            # LSP is 0-based; Godot's editor gutter is 1-based.
            line = int(start.get("line", 0)) + 1
            col = int(start.get("character", 0)) + 1
            sev = SEVERITY.get(d.get("severity", 1), "ERROR")
            text = " ".join(str(d.get("message", "")).split())
            key = (path, line, col, text)
            if key in seen:
                continue
            seen.add(key)
            lines.append(f"{path}:{line}:{col}: {sev}: {text}")

    client.request("initialize", {
        "processId": os.getpid(),
        "rootPath": root_abs,
        "rootUri": "file://" + root_abs,
        "capabilities": {"textDocument": {"publishDiagnostics": {"relatedInformation": True}}},
    })
    client.drain(15.0, sink)
    client.notify("initialized", {})

    for path in files:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        client.notify("textDocument/didOpen", {
            "textDocument": {
                "uri": "file://" + path,
                "languageId": "gdscript",
                "version": 1,
                "text": text,
            }
        })
    # Give the analyzer time to work through every opened document.
    client.drain(wait, sink)

    for path in files:
        client.notify("textDocument/didClose", {"textDocument": {"uri": "file://" + path}})
    try:
        client.notify("shutdown", {})
    except OSError:
        pass
    sock.close()
    lines.sort()
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="project directory")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6005)
    parser.add_argument("--wait", type=float, default=60.0,
                        help="seconds of quiet to wait for diagnostics")
    args = parser.parse_args()

    lines = collect(args.root, args.host, args.port, args.wait)
    for line in lines:
        print(line)
    warnings = sum(1 for l in lines if ": WARNING: " in l)
    errors = sum(1 for l in lines if ": ERROR: " in l)
    print(f"# {len(lines)} diagnostics ({errors} errors, {warnings} warnings)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
