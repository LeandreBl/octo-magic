"""The octopus mage's body animations and tentacle texture, made with
PixelLab (server/art.py).

Seen from straight above, head to the top: the game turns it toward where it
goes. Its ground tentacles are not in the sprite: game/tentacle.gd animates
them under it with physics, as lines textured with TENTACLE.

Every animation starts from BODY (tools/octo_body.png): the still
tools/octo_still.png (a PixelLab pixen still: high top-down, seed 3, LOOK,
edited by PixelLab so one tentacle grips the staff) edited by pixen with
NO_TENTACLES, seed 3: the body, the hat and the staff in a short tentacle.
Each animation is a PixMiniMax one, written to assets/octo/<anim>.png: a strip
of FRAMES square frames of SIZE pixels, read by game/player.gd. Each run draws
new ones.

PixMiniMax strikes toward the bottom of the image whatever the prompt: the
strike and the channel are drawn on the still turned 180 degrees, then turned
back so they strike forward (up).

Run: python3 tools/make_octopus.py  (--tentacle: also a new tentacle texture)
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
BODY = ROOT / "tools/octo_body.png"
SIZE = 96
FRAMES = 8
LOOK = ("purple octopus wizard seen from directly above, bird's-eye view at 90 degrees, top-down game sprite:"
        " we see the top of its round pointed indigo wizard hat with a gold band in the center, eight curly purple"
        " tentacles spread out radially around it like a star, a wooden staff with a glowing blue crystal tip held"
        " by one tentacle pointing up, symmetric overhead view, no face visible")
NO_TENTACLES = ("remove all the ground tentacles: keep only the round purple body with the indigo wizard hat seen"
                " from above, and the wooden staff with its blue crystal held by one short tentacle; nothing around the"
                " body")
IDLE = ("octopus body resting in place seen from directly above: it breathes gently, the hat sways a little, the"
        " crystal of the staff glows softly, seamless loop")
CAST = ("the tentacle coiled around the staff keeps gripping it and strikes with it: it swings the staff forward so"
        " it tilts and leans out ahead toward the bottom of the image, like a club blow at an enemy in front, a small"
        " blue spark at the crystal on impact, then it brings the staff back to its starting position. The staff"
        " never leaves the tentacle")
# Channeling starts from the cast's frame CHANNEL_FROM: the staff leaning forward.
CHANNEL = ("the tentacle keeps gripping the staff and holds it leaning forward toward the bottom of the image without"
           " moving it, the crystal at its tip pulses and crackles with a continuous stream of blue magic sparks,, the"
           " body breathes gently, seamless loop")
CHANNEL_FROM = 4
# One tentacle lying horizontally, base on the left: game/tentacle.gd stretches
# it along its chain.
TENTACLE = ("one single straight purple octopus tentacle lying horizontally, seen from directly above, thick round"
            " base on the left tapering smoothly to a thin pointed tip on the right, small pink suction cups along its"
            " middle, dark purple outline, game sprite")


def _turn(px: bytes) -> bytes:
    """A SIZE x SIZE RGBA frame turned 180 degrees."""
    pixels = [px[i:i + 4] for i in range(0, len(px), 4)]
    return b"".join(reversed(pixels))


def _b64(png: bytes) -> dict:
    return {"type": "base64", "base64": base64.b64encode(png).decode()}


def animate(first: bytes, motion: str, last: bytes | None = None, size: int = SIZE, frames: int = FRAMES) -> list[bytes]:
    """PixMiniMax from the RGBA frame `first` (toward `last` if given)."""
    body = {"first_frame": _b64(sheet.write_png(size, size, first)), "description": motion, "frame_count": frames,
            "no_background": True, "view": "high top-down"}
    if last:
        body["last_frame"] = _b64(sheet.write_png(size, size, last))
    job = art._request("POST", "/animate-pixminimax", body)["background_job_id"]
    while (r := art._request("GET", f"/background-jobs/{job}"))["status"] in ("pending", "processing"):
        time.sleep(10)
    images = r["last_response"]["images"][1:]  # the first one is the input itself
    return [bytes(sheet.read_png(base64.b64decode(i["base64"]))[2]) for i in images]


def _write(name: str, frames: list[bytes], size: int = SIZE) -> None:
    rows = b"".join(b"".join(f[y * size * 4:(y + 1) * size * 4] for f in frames) for y in range(size))
    (OUT / f"{name}.png").write_bytes(sheet.write_png(size * len(frames), size, rows))
    print(name, len(frames))


def tentacle() -> bytes:
    res = art._request("POST", "/create-image-pixen", {
        "description": TENTACLE, "image_size": {"width": 128, "height": 32}, "no_background": True,
        "view": "high top-down", "outline": "single color black outline", "detail": "medium detail"})
    return base64.b64decode(res["image"]["base64"])


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if "--tentacle" in sys.argv:
        (OUT / "tentacle.png").write_bytes(tentacle())
    body = bytes(sheet.read_png(BODY.read_bytes())[2])
    _write("idle", animate(body, IDLE))
    cast = animate(_turn(body), CAST)  # turned: see the docstring
    _write("cast", [_turn(f) for f in cast])
    _write("channel", [_turn(f) for f in animate(cast[CHANNEL_FROM], CHANNEL)])


if __name__ == "__main__":
    main()
