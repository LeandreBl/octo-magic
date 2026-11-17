"""PixelLab client: animated VFX sprite sheets and icons for spells.

Token: PIXELLAB_TOKEN, or the file ~/.config/octo-magic/pixellab.token.
"""

import base64
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
TOKEN_FILE = Path.home() / ".config/octo-magic/pixellab.token"


def token() -> str:
    tok = os.environ.get("PIXELLAB_TOKEN")
    if not tok and TOKEN_FILE.exists():
        tok = TOKEN_FILE.read_text().strip()
    return tok or ""


def _request(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503, 529) or attempt == 3:  # busy: wait and retry
                raise
            time.sleep(10 * (attempt + 1))


def _download(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def vfx(description: str, name: str, timeout: float = 300) -> tuple[bytes, dict]:
    """One animated effect -> (png sheet, {w, h, frames, fps, cols})."""
    job = _request("POST", "/vfx", {"description": description, "artist": "lite", "name": name})
    deadline = time.monotonic() + timeout
    while True:
        time.sleep(6)
        done = _request("GET", f"/background-jobs/{job['background_job_id']}")
        if done["status"] == "completed":
            break
        if done["status"] != "processing" or time.monotonic() > deadline:
            raise RuntimeError(f"vfx {name}: {done['status']}")
    res = done["last_response"]
    files = res["files"]
    png = _download(next(u for f, u in files.items() if f.endswith(".png") and "normals" not in f))
    meta = json.loads(_download(next(u for f, u in files.items() if f.endswith(".json"))))
    frames = meta["frames"]
    frames = list(frames.values()) if isinstance(frames, dict) else frames
    w, h = frames[0]["frame"]["w"], frames[0]["frame"]["h"]
    sheet_w = max(f["frame"]["x"] for f in frames) + w
    fps = max(1, round(1000 / (frames[0].get("duration") or 83)))
    return png, {"w": w, "h": h, "frames": len(frames), "fps": fps, "cols": sheet_w // w}


def icon(description: str) -> bytes:
    res = _request("POST", "/create-image-pixen", {
        "description": description, "image_size": {"width": 32, "height": 32},
        "no_background": True, "view": "side",
        "outline": "single color black outline", "detail": "medium detail",
    })
    return base64.b64decode(res["image"]["base64"])
