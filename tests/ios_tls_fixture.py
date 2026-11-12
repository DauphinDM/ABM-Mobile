#!/usr/bin/env python3
"""Loopback-only simulator fixture; never contacts a real game or user PC."""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[1]
work = tempfile.TemporaryDirectory(prefix="abm-ios-fixture-")
folder = Path(work.name)
subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes", "-days", "1", "-subj", "/CN=ABM Simulator Test", "-keyout", str(folder / "key.pem"), "-out", str(folder / "cert.pem")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(folder / "cert.pem", folder / "key.pem")
der = ssl.PEM_cert_to_DER_cert((folder / "cert.pem").read_text())
secret = secrets.token_hex(32)
listener = socket.socket()
listener.bind(("127.0.0.1", 0)); listener.listen(4)
invite = {"v": 1, "host": "127.0.0.1", "port": listener.getsockname()[1], "sha256": hashlib.sha256(der).hexdigest(), "secret": secret}
link = "abm://pair/" + base64.urlsafe_b64encode(json.dumps(invite).encode()).decode().rstrip("=")
resources = root / "ios/ABMMobileUITests/Resources"
resources.mkdir(exist_ok=True)
(resources / "TestConfig.json").write_text(json.dumps({"invitation": link}))
target = {"session": "ios-test", "vehicle": 42, "generation": "test-1", "map": "gridmap_v2", "server": "", "port": 0}
state = {"connected": True, "controlsAvailable": True, "vehicleId": 42, "vehicleOwned": True, "sandboxAllowed": True, "map": "gridmap_v2", "vehicle": "Simulator fixture", "telemetry": {"speed": 0, "rpm": 900, "fuel": .5}, "capabilities": {"power": True}}
snapshot = {"kind": "snapshot", "v": 1, "target": target, "state": state, "busy": False}
photo = "c" * 64
preview = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAAUACADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFgEBAQEAAAAAAAAAAAAAAAAAAAUG/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8ArgGBVQAAAAAH/9k="

def handle(raw):
    try:
        with context.wrap_socket(raw, server_side=True) as peer:
            peer.settimeout(.2)
            buffer = b""; paired = False; stale = False; last = 0; sequence = 0
            library = {"catalog": [], "configs": [], "configsModel": ""}
            def send(value): peer.sendall(json.dumps(value, separators=(",", ":")).encode() + b"\n")
            while True:
                try:
                    data = peer.recv(32768)
                    if not data: break
                    buffer += data
                except socket.timeout: pass
                assert len(buffer) <= 32768
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    value = json.loads(line)
                    if not paired:
                        assert value["kind"] == "pair" and value["v"] == 1 and secrets.compare_digest(value["secret"], secret)
                        paired = True; send({"kind": "pending"})
                        time.sleep(.25); send({"kind": "ready"}); send(snapshot)
                    elif value["kind"] == "ping": send({"kind": "pong", "stamp": value["stamp"]})
                    elif value["kind"] == "thumbnail":
                        assert value["id"] == photo
                        send({"kind": "thumbnail", "id": photo, "jpeg": preview})
                    else:
                        sequence += 1
                        assert value["kind"] == "command" and value["target"] == target and value["seq"] == sequence
                        action = value["action"]
                        assert action == ["catalog", "configs", "spawn", "power", "repair"][sequence - 1]
                        if action == "catalog": library["catalog"] = [{"id": "testcar", "name": "Fixture car", "photo": photo}]
                        elif action == "configs":
                            assert value["args"]["model"] == "testcar"
                            library.update(configsModel="testcar", configs=[{"id": "testcar/base", "name": "Factory test", "photo": photo}])
                        elif action == "spawn": assert value["args"]["config"] == "testcar/base"
                        elif action == "power": assert value["args"]["value"] == 2
                        elif action == "repair":
                            Path(os.environ.get("ABM_IOS_COMMAND_MARKER", str(folder / "command-ok"))).touch()
                            stale = True
                        send({"kind": "receipt", "seq": sequence, "message": "Fixture accepted " + action})
                        if not stale: send(dict(snapshot, **library))
                if paired and not stale and time.monotonic() - last > .25:
                    send(dict(snapshot, **library)); last = time.monotonic()
    except (ssl.SSLError, OSError): pass

print("Simulator TLS fixture ready", flush=True)
while True:
    raw, _ = listener.accept()
    threading.Thread(target=handle, args=(raw,), daemon=True).start()
