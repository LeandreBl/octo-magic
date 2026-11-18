"""Generate the spell forge's art with PixelLab (server/art.py), for ui/forge.gd:
the table, the parchment, a flickering candle, the quill and the runes.
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
RUNE = ("a single ancient norse rune letter drawn as thick glowing golden yellow strokes, only gold and yellow"
        " colors, no circle, no stone, centered")
# Elder Futhark runes (runes.png, one per frame): their shapes, so they differ.
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


def image(description: str, w: int, h: int, background: bool = False) -> bytes:
    res = art._request("POST", "/create-image-pixen", {
        "description": description, "image_size": {"width": w, "height": h},
        "no_background": not background, "view": "high top-down",
        "outline": "single color black outline", "detail": "highly detailed",
    }, timeout=180)
    return base64.b64decode(res["image"]["base64"])


def table() -> bytes:
    return image("seamless tileable texture of dark oak wooden table planks seen from above, horizontal boards,"
                 " warm brown wood grain, a few nail heads, no objects, fills the whole image", 128, 128, True)


def parchment() -> bytes:
    png = image("a large blank parchment sheet lying flat seen from above, an even smooth light cream beige"
                 " paper filling the whole image, a thin darker brown aged rim and slightly curled corners,"
                 " clean plain center with no holes, no stains, no white spots, nothing written on it", 256, 192, True)
    return _clear(png)


def _clear(png: bytes) -> bytes:
    """The flat background PixelLab leaves around the sheet (the corner's color) -> transparent."""
    w, h, px = sheet.read_png(png)
    corner = px[0:3]
    for i in range(0, len(px), 4):
        if px[i:i + 3] == corner:
            px[i + 3] = 0
    return sheet.write_png(w, h, bytes(px))


def candle() -> bytes:
    base = art.sprite("a single lit wax candle standing in a small brass candlestick holder, cream wax with drips,"
                      " a bright small orange flame on top, seen from the front", 64, "highly detailed")
    return _strip(art.animate(base, "the candle flame flickers and sways gently, the candle itself stays still", 8)[-8:])


def quill() -> bytes:
    return art.sprite("a white feather quill pen with a dark ink-wet nib, tilted, the nib pointing down left", 48,
                      "highly detailed")


def runes() -> bytes:
    return _strip([art.icon(f"{RUNE}: the rune {r}") for r in RUNES])


JOBS = {"table": table, "parchment": parchment, "candle": candle, "quill": quill, "runes": runes}


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
