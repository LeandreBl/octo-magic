"""The octopus mage's sprites, made with PixelLab (server/art.py).

Exports the PixelLab character CHARACTER (8 directions, animations "walk" and
"idle") to assets/octo/<anim>_<direction>.png: one horizontal strip of square
frames per animation and direction, read by game/player.gd.

Run: python3 tools/make_octopus.py         # export CHARACTER
     python3 tools/make_octopus.py --new   # generate a new character and its animations, print its id
"""

import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/octo"
CHARACTER = "a08bf421-3779-488d-9113-967eef4a2d57"
DIRECTIONS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
LOOK = ("cute purple octopus wizard, round purple head with big shiny eyes, pointed indigo wizard hat"
        " with a gold band, small violet robe collar, eight curly purple tentacles, holding a wooden"
        " magic staff with a glowing tip, fantasy pixel art game hero")
ANIMATIONS = {
    "walk": "scuttling forward on its eight tentacles, the tentacles ripple in a fast rolling wave pushing"
            " the body along, body bobbing up and down, hat wobbling, looping walk cycle",
    "idle": "floating in place, the eight tentacles slowly curl and sway like seaweed, body gently bobbing,"
            " looping idle",
}


def _wait(job: str) -> None:
    while art._request("GET", f"/background-jobs/{job}")["status"] in ("pending", "processing"):
        time.sleep(10)


def new() -> str:
    c = art._request("POST", "/create-character-v3", {
        "description": LOOK, "image_size": {"width": 64, "height": 64}, "view": "low top-down",
        "template_id": "custom", "outline": "single color black outline", "detail": "medium detail",
        "name": "octo-mage"})
    _wait(c["background_job_id"])
    for name, action in ANIMATIONS.items():
        r = art._request("POST", "/characters/animations", {
            "character_id": c["character_id"], "animation_name": name, "action_description": action,
            "mode": "v3", "frame_count": 8, "directions": DIRECTIONS, "keep_first_frame": False})
        for job in r["background_job_ids"]:
            _wait(job)
    return c["character_id"]


def _png(url: str) -> tuple[int, int, bytearray]:
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})  # the file host refuses urllib's
    with urllib.request.urlopen(req, timeout=60) as r:
        return sheet.read_png(r.read())


def export(character: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    c = art._request("GET", f"/characters/{character}")
    for a in c["animations"]:
        for d in a["directions"]:
            frames = [_png(u) for u in d["frames"]]
            w, h = frames[0][0], frames[0][1]
            rows = b"".join(b"".join(bytes(f[2][y * w * 4:(y + 1) * w * 4]) for f in frames) for y in range(h))
            (OUT / f"{a['display_name']}_{d['direction']}.png").write_bytes(sheet.write_png(w * len(frames), h, rows))
            print(a["display_name"], d["direction"], len(frames), f"{w}x{h}")


if __name__ == "__main__":
    export(new() if "--new" in sys.argv else CHARACTER)
