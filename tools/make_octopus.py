"""The octopus mage's sprites, made with PixelLab (server/art.py).

Seen from straight above, head to the top: the game turns it toward where it
goes. One still (pixen, high top-down), then each animation from it
(PixMiniMax), written to assets/octo/<anim>.png: a strip of FRAMES square
frames of SIZE pixels, read by game/player.gd. Each run draws new ones.

Run: python3 tools/make_octopus.py
"""

import base64
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/octo"
SIZE = 96  # the still (64) centered on a larger canvas: room for the tentacles to spread
FRAMES = 8
LOOK = ("purple octopus wizard seen from directly above, bird's-eye view at 90 degrees, top-down game sprite:"
        " we see the top of its round pointed indigo wizard hat with a gold band in the center, eight curly purple"
        " tentacles spread out radially around it like a star, a wooden staff with a glowing blue crystal tip held"
        " by one tentacle pointing up, symmetric overhead view, no face visible")
ANIMATIONS = {
    "walk": "octopus swimming forward toward the top of the image, seen from directly above: all eight tentacles"
            " pulse together, sweeping back and contracting then spreading out wide again, a strong rhythmic"
            " jet-propulsion stroke, seamless loop",
    "idle": "octopus resting in place seen from directly above: the eight tentacles slowly undulate and curl at"
            " their tips like seaweed, the body breathes gently, seamless loop",
}


def _b64(png: bytes) -> dict:
    return {"type": "base64", "base64": base64.b64encode(png).decode()}


def still() -> bytes:
    r = art._request("POST", "/create-image-pixen", {
        "description": LOOK, "image_size": {"width": 64, "height": 64}, "view": "high top-down",
        "direction": "north", "no_background": True, "outline": "single color black outline",
        "detail": "medium detail", "seed": 3})
    w, h, px = sheet.read_png(base64.b64decode(r["image"]["base64"]))
    out = bytearray(SIZE * SIZE * 4)  # centered on the SIZE canvas
    ox, oy = (SIZE - w) // 2, (SIZE - h) // 2
    for y in range(h):
        out[((oy + y) * SIZE + ox) * 4:((oy + y) * SIZE + ox + w) * 4] = px[y * w * 4:(y + 1) * w * 4]
    return sheet.write_png(SIZE, SIZE, bytes(out))


def animate(first: bytes, motion: str) -> list[bytearray]:
    job = art._request("POST", "/animate-pixminimax", {
        "first_frame": _b64(first), "description": motion, "frame_count": FRAMES, "no_background": True,
        "view": "high top-down", "direction": "north"})["background_job_id"]
    while (r := art._request("GET", f"/background-jobs/{job}"))["status"] in ("pending", "processing"):
        time.sleep(10)
    images = r["last_response"]["images"][1:]  # the first one is the still itself
    return [sheet.read_png(base64.b64decode(i["base64"]))[2] for i in images]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    first = still()
    for name, motion in ANIMATIONS.items():
        frames = animate(first, motion)
        rows = b"".join(b"".join(bytes(f[y * SIZE * 4:(y + 1) * SIZE * 4]) for f in frames) for y in range(SIZE))
        (OUT / f"{name}.png").write_bytes(sheet.write_png(SIZE * len(frames), SIZE, rows))
        print(name, len(frames))


if __name__ == "__main__":
    main()
