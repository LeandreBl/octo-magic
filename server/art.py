"""PixelLab client: animated VFX sprite sheets and icons for spells, and
animated sprites for the monsters, seen from above (tools/make_monsters.py).

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


def icon(description: str, size: int = 32) -> bytes:
    res = _request("POST", "/create-image-pixen", {
        "description": description, "image_size": {"width": size, "height": size},
        "no_background": True, "view": "side",
        "outline": "single color black outline", "detail": "medium detail",
    })
    return base64.b64decode(res["image"]["base64"])


def styled(style: bytes, description: str, timeout: float = 600) -> list[bytes]:
    """Creatures drawn in the framing and look of the PNG `style` (its size,
    square) -> ~25 choices, PNGs."""
    w, h = _png_size(style)
    job = _request("POST", "/generate-with-style-v2", {
        "style_images": [{"image": _b64(style), "width": w, "height": h}], "description": description,
        "style_description": "seen from straight above like the reference, same outline and shading",
        "no_background": True})
    return [base64.b64decode(i["base64"]) for i in _wait(job, f"style {description[:40]}", timeout)["images"]]


def edit(png: bytes, change: str, timeout: float = 600) -> bytes:
    """`png` with `change` (Pixen edit: its pose and framing kept) -> PNG of its size."""
    job = _request("POST", "/edit-image-pixen", {"image": _b64(png), "description": change, "no_background": True})
    return base64.b64decode(_wait(job, f"edit {change[:40]}", timeout)["image"]["base64"])


def _b64(png: bytes) -> dict:
    return {"type": "base64", "base64": base64.b64encode(png).decode()}


def _png_size(png: bytes) -> tuple[int, int]:
    return int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")


def animate(png: bytes, action: str, frames: int = 8, timeout: float = 600) -> list[bytes]:
    """`png` (first frame, seen from above) doing `action` (PixMiniMax) -> the
    frames after it, PNGs of its size."""
    job = _request("POST", "/animate-pixminimax", {
        "first_frame": _b64(png), "description": action, "frame_count": frames, "no_background": True, "view": "high top-down",
    })
    res = _wait(job, f"animate {action[:40]}", timeout)
    return [base64.b64decode(i["base64"]) for i in res["images"][1:]]  # the first one is the input itself
