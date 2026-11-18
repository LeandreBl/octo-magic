"""Generate the spell forge's art with PixelLab (server/art.py), for ui/forge.gd:
a wizard's study, its table seen at three quarters (books, candles, papers),
chalk magic circles drawn on it (a big one, a small one per word) and chalk
glyphs.
Writes assets/forge/<name>.png; existing files are kept (delete one to redo it).

Run: python3 tools/make_forge.py [name ...]
"""

import base64
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
sys.path.insert(0, str(ROOT / "tools"))
import art  # noqa: E402
import sheet  # noqa: E402
from make_monsters import _strip  # noqa: E402

OUT = ROOT / "assets/forge"
# Elder Futhark runes (glyphs.png, one per frame): their shapes, so they differ.
RUNES = [
    "Kenaz: an arrowhead shape like the less-than sign <",
    "Gebo: a big X cross",
    "Hagalaz: an H with a slanted middle bar",
    "Isa: one single vertical line",
    "Tiwaz: an upward arrow, a vertical line with two slanted lines at the top",
    "Algiz: a vertical line with two branches going up, like a Y with a long stem",
    "Sowilo: a zigzag lightning shape like an angular S",
    "Berkano: like a capital letter B made of straight lines",
    "Mannaz: like an M with a diagonal X between its two vertical lines",
    "Othala: a diamond on two diagonal legs",
    "Dagaz: two triangles touching at their tips between two vertical lines, like a bowtie",
    "Ingwaz: a small diamond",
]


def image(description: str, w: int, h: int, background: bool = False, outline: str = "lineless") -> bytes:
    res = art._request("POST", "/create-image-pixen", {
        "description": description, "image_size": {"width": w, "height": h},
        "no_background": not background, "view": "high top-down",
        "outline": outline, "detail": "highly detailed",
    }, timeout=180)
    return base64.b64decode(res["image"]["base64"])


def room() -> bytes:
    return image("high three-quarter view of a big empty wooden table in a dark medieval room at night, the table"
                 " top takes most of the frame, a few small lit candles at its four corners, small stacks of old"
                 " books at the back left, loose small parchment sheets at the back right, wide empty bare wooden"
                 " center, warm candlelight", 428, 240, True)


CHALK = ("drawn by hand with white chalk on a dark wooden table, slightly smudged dusty chalk strokes,"
         " only white and pale grey chalk colors, flat seen from straight above, transparent background")


def chalk(png: bytes) -> bytes:
    """Only the chalk: dark pixels (outline, fill) cleared, the rest white with
    its lightness as alpha, so ui/forge.gd tints it (chalk, glowing gold)."""
    w, h, px = sheet.read_png(png)
    for i in range(0, len(px), 4):
        light = sum(px[i:i + 3]) // 3
        px[i:i + 4] = bytes([255, 255, 255, min(px[i + 3], max(0, light - 100) * 255 // 155)])
    return sheet.write_png(w, h, bytes(px))


def circle() -> bytes:
    return chalk(image(f"a big round magic summoning circle: two thin concentric rings with a band of small arcane"
                 f" glyphs between them, a hexagram star inside, an empty plain center, {CHALK}", 192, 192))


def seal() -> bytes:
    return chalk(image("a small round magic circle drawn with white chalk on a plain pure black background: one thin"
                       " white ring, a second thinner inner ring with tiny runes between them, the middle left"
                       " completely empty and black, flat, seen from straight above", 64, 64, True))


def glyphs() -> bytes:
    return chalk(_strip([art.icon(f"a single ancient rune letter drawn as thick white chalk strokes on nothing, only white"
                            f" and pale grey, no circle, no stone, centered: the rune {r}") for r in RUNES]))


JOBS = {"room": room, "circle": circle, "seal": seal, "glyphs": glyphs}


def _make(name: str) -> None:
    try:
        (OUT / f"{name}.png").write_bytes(JOBS[name]())
        print("ok", name)
    except Exception as e:  # keep going: one failure must not lose the rest
        print("FAILED", name, e)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    with ThreadPoolExecutor(5) as pool:
        for name in JOBS:
            if (not only or name in only) and not (OUT / f"{name}.png").exists():
                pool.submit(_make, name)


if __name__ == "__main__":
    main()
