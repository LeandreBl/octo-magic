"""The octopus mage's body animations and tentacle texture, made with
PixelLab (server/art.py).

Seen from straight above, head to the top: the game turns it toward where it
goes. Its ground tentacles are not in the sprite: game/tentacle.gd animates
them under it with physics, as lines textured with TENTACLE.

Every animation starts from BODY (tools/octo_body.png): the still
tools/octo_still.png (a PixelLab pixen still: high top-down, seed 3, LOOK,
edited by PixelLab so one tentacle grips the staff) edited by pixen with
NO_TENTACLES, seed 3: the body, the hat and the staff in a short tentacle.
The animation is a PixMiniMax one, written to assets/octo/idle.png: a strip
of FRAMES square frames of SIZE pixels, read by game/player.gd (which draws the
gem's flash on a cast itself). Each run draws new ones. assets/octo/cast.png
(the staff struck forward) was drawn by an earlier version of this script
(git show ec3957d^:tools/make_octopus.py); redraw it with the body.

Run: python3 tools/make_octopus.py  (the body; --tentacle: 64 tentacles to
tools/tentacle_choices/, then --pick <n> copies one to assets/octo/tentacle.png)
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
# One tentacle in the style of the still's own (a 32-pixel crop of its left
# tentacles as the style reference), drawn 1:1 by game/tentacle.gd along its
# chain. PixelLab draws 64 of them, the tip curled on the left and the base cut
# by the right edge: each is cropped and flipped (base on the left), then one is
# picked by eye.
TENTACLE = ("one single straight octopus tentacle lying horizontally across the whole image, thick on the left, thin"
            " pointed tip on the right, purple with a light pink highlight line, black outline")
TENTACLE_STYLE = "the chunky purple tentacle of the reference, same thickness and colors"


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


def tentacles() -> list[tuple[int, int, bytes]]:
    """64 tentacles of 32x32 pixels as (w, h, RGBA), in the still's style."""
    w, _, px = sheet.read_png(STILL.read_bytes())
    crop = b"".join(bytes(px[((30 + y) * w + 4) * 4:((30 + y) * w + 36) * 4]) for y in range(32))
    job = art._request("POST", "/generate-with-style-v2", {
        "style_images": [{"image": _b64(sheet.write_png(32, 32, crop)), "width": 32, "height": 32}],
        "description": TENTACLE, "style_description": TENTACLE_STYLE, "no_background": True})
    return [sheet.read_png(base64.b64decode(i["base64"])) for i in art._wait(job, "tentacles", 600)["images"]]


def tentacle(img: tuple[int, int, bytes]) -> bytes:
    """One of tentacles(), cropped to its tentacle and flipped: base on the left."""
    w, h, px = img
    cols = [x for x in range(w) for y in range(h) if px[(y * w + x) * 4 + 3]]
    rows = [y for y in range(h) for x in range(w) if px[(y * w + x) * 4 + 3]]
    x0, x1, y0, y1 = min(cols), max(cols) + 1, min(rows), max(rows) + 1
    out = b"".join(bytes(px[(y * w + x) * 4:(y * w + x) * 4 + 4]) for y in range(y0, y1) for x in reversed(range(x0, x1)))
    return sheet.write_png(x1 - x0, y1 - y0, out)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if "--tentacle" in sys.argv:  # then pick one: --pick <index>
        imgs = tentacles()
        (ROOT / "tools/tentacle_choices").mkdir(exist_ok=True)
        for i, img in enumerate(imgs):
            (ROOT / f"tools/tentacle_choices/{i}.png").write_bytes(tentacle(img))
        return
    if "--pick" in sys.argv:
        pick = ROOT / f"tools/tentacle_choices/{sys.argv[sys.argv.index('--pick') + 1]}.png"
        (OUT / "tentacle.png").write_bytes(pick.read_bytes())
        return
    body = bytes(sheet.read_png(BODY.read_bytes())[2])
    _write("idle", animate(body, IDLE))


if __name__ == "__main__":
    main()
