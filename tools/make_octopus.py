"""The octopus mage's animations, made with PixelLab (server/art.py).

Seen from straight above, head to the top: the game turns it toward where it
goes. Every animation starts from STILL (tools/octo_still.png): a PixelLab
pixen still (high top-down, seed 3, LOOK), edited by PixelLab so one tentacle
grips the staff, then the ground tentacle that grips it erased by hand.
Each animation is a PixMiniMax one, written to assets/octo/<anim>.png: a strip
of FRAMES square frames of SIZE pixels, read by game/player.gd. Each run draws
new ones.

PixMiniMax strikes toward the bottom of the image whatever the prompt: the
strike and the channel are drawn on the still turned 180 degrees, then turned
back so they strike forward (up).

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
STILL = ROOT / "tools/octo_still.png"
SIZE = 96
FRAMES = 8
LOOK = ("purple octopus wizard seen from directly above, bird's-eye view at 90 degrees, top-down game sprite:"
        " we see the top of its round pointed indigo wizard hat with a gold band in the center, eight curly purple"
        " tentacles spread out radially around it like a star, a wooden staff with a glowing blue crystal tip held"
        " by one tentacle pointing up, symmetric overhead view, no face visible")
ANIMATIONS = {  # drawn on the still as it is
    "walk": "walking cycle seen from directly above: the octopus moves forward (up), the tentacles push off and glide"
            " backward under its body toward the bottom of the image, stretching out behind it, then curl forward"
            " again; alternate tentacles, smooth continuous propulsion; the staff stays held, seamless loop",
    "idle": "octopus resting in place seen from directly above: the eight tentacles slowly undulate and curl at"
            " their tips like seaweed, the body breathes gently, seamless loop",
}
CAST = ("the tentacle coiled around the staff keeps gripping it and strikes with it: it swings the staff forward so"
        " it tilts and leans out ahead toward the bottom of the image, like a club blow at an enemy in front, a small"
        " blue spark at the crystal on impact, then it brings the staff back to its starting position. The staff"
        " never leaves the tentacle")
# Channeling starts from the cast's frame CHANNEL_FROM: the staff leaning forward.
CHANNEL = ("the tentacle keeps gripping the staff and holds it leaning forward toward the bottom of the image without"
           " moving it, the crystal at its tip pulses and crackles with a continuous stream of blue magic sparks, the"
           " other tentacles sway gently, seamless loop")
CHANNEL_FROM = 4


def _turn(px: bytes) -> bytes:
    """A SIZE x SIZE RGBA frame turned 180 degrees."""
    pixels = [px[i:i + 4] for i in range(0, len(px), 4)]
    return b"".join(reversed(pixels))


def animate(first: bytes, motion: str) -> list[bytes]:
    job = art._request("POST", "/animate-pixminimax", {
        "first_frame": {"type": "base64", "base64": base64.b64encode(sheet.write_png(SIZE, SIZE, first)).decode()},
        "description": motion, "frame_count": FRAMES, "no_background": True,
        "view": "high top-down"})["background_job_id"]
    while (r := art._request("GET", f"/background-jobs/{job}"))["status"] in ("pending", "processing"):
        time.sleep(10)
    images = r["last_response"]["images"][1:]  # the first one is the input itself
    return [bytes(sheet.read_png(base64.b64decode(i["base64"]))[2]) for i in images]


def _write(name: str, frames: list[bytes]) -> None:
    rows = b"".join(b"".join(f[y * SIZE * 4:(y + 1) * SIZE * 4] for f in frames) for y in range(SIZE))
    (OUT / f"{name}.png").write_bytes(sheet.write_png(SIZE * len(frames), SIZE, rows))
    print(name, len(frames))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    still = bytes(sheet.read_png(STILL.read_bytes())[2])
    for name, motion in ANIMATIONS.items():
        _write(name, animate(still, motion))
    cast = animate(_turn(still), CAST)  # turned: see the docstring
    _write("cast", [_turn(f) for f in cast])
    _write("channel", [_turn(f) for f in animate(cast[CHANNEL_FROM], CHANNEL)])


if __name__ == "__main__":
    main()
