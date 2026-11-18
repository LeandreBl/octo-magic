"""PixelLab client: animated VFX sprite sheets and icons for spells, and
animated sprites for the monsters (tools/make_monsters.py).

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


def _request(method: str, path: str, body: dict | None = None, timeout: float = 60) -> dict:
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503, 529) or attempt == 3:  # busy: wait and retry
                e.msg += ": " + e.read().decode(errors="replace")[:500]
                raise
            time.sleep(10 * (attempt + 1))


def _download(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def _wait(job: dict, what: str, timeout: float) -> dict:
    """Polls a background job until done -> its last response."""
    deadline = time.monotonic() + timeout
    while True:
        time.sleep(6)
        done = _request("GET", f"/background-jobs/{job['background_job_id']}")
        if done["status"] == "completed":
            return done["last_response"]
        if done["status"] != "processing" or time.monotonic() > deadline:
            raise RuntimeError(f"{what}: {done['status']} {str(done.get('last_response'))[:300]}")


def vfx(description: str, name: str, timeout: float = 300) -> tuple[bytes, dict]:
    """One animated effect -> (png sheet, {w, h, frames, fps, cols})."""
    job = _request("POST", "/vfx", {"description": description, "artist": "lite", "name": name})
    res = _wait(job, f"vfx {name}", timeout)
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


def sprite(description: str, size: int, detail: str = "medium detail") -> bytes:
    """A creature seen from the side, facing right (east): size x size PNG."""
    res = _request("POST", "/create-image-pixen", {
        "description": description, "image_size": {"width": size, "height": size},
        "no_background": True, "view": "side", "direction": "east",
        "outline": "single color black outline", "detail": detail,
    })
    return base64.b64decode(res["image"]["base64"])


def animate(png: bytes, action: str, frames: int = 8, timeout: float = 400) -> list[bytes]:
    """`png` (first frame) doing `action` -> the frames, PNGs of its size."""
    job = _request("POST", "/animate-with-text-v3", {
        "first_frame": {"type": "base64", "base64": base64.b64encode(png).decode()},
        "action": action, "frame_count": frames, "no_background": True,
    })
    res = _wait(job, f"animate {action[:40]}", timeout)
    return [base64.b64decode(i["base64"]) for i in res["images"]]
