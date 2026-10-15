"""Exercise installed TranslateGemma against public fixtures using production Swift prompts.

This tests the local service/prompt, not the uncompiled Swift HTTP adapter or audio pipeline.
Uses only the Python standard library and an explicit loopback connection without redirects.
"""
import http.client
import json
from pathlib import Path
import subprocess
import sys
import time

fixtures = json.loads((Path(__file__).resolve().parent.parent / "docs/translation-quality-cases.json").read_text())
for case in fixtures:
    prompt = subprocess.run([sys.argv[1], case["source"]], check=True, capture_output=True, text=True).stdout.rstrip("\n")
    request = {
        "model": "translategemma:4b",
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "keep_alive": "5m",
        "options": {"temperature": 0.2, "num_ctx": 4096, "num_predict": 384},
    }
    connection = http.client.HTTPConnection("127.0.0.1", 11434, timeout=75)
    started = time.monotonic()
    try:
        connection.request("POST", "/api/chat", json.dumps(request).encode(), {"Content-Type": "application/json"})
        response = connection.getresponse()
        data = json.loads(response.read())
        if response.status != 200 or not data.get("done") or data.get("done_reason") == "length":
            raise RuntimeError("Local model returned an unsuccessful or incomplete response")
        translated = data["message"]["content"].strip()
        if not translated:
            raise RuntimeError("Local model returned no translation")
        print(json.dumps({"source": case["source"], "translation": translated,
                          "seconds": round(time.monotonic() - started, 2)}, ensure_ascii=False), flush=True)
    finally:
        connection.close()
