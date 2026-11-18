"""Generate the in-game sprites of the base spells (game/spells.json) with
PixelLab (server/art.py): the flying projectile (looping) and its impact
burst (one-shot), as strips following server/sheet.py.

Writes assets/spells/<id>.png and <id>_burst.png and records them in
game/spells.json (body.sheet / body.burst_sheet, bundle res://assets/spells).
Existing files are kept (delete one to redo it). Beams are drawn by the
engine (spell_body.gd); a cone's sheet is its whole spray, apex on the left.

Run: python3 tools/make_spells.py [id ...]
"""

import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/spells"
SPELLS_JSON = ROOT / "game/spells.json"
BOLT = ". Top-down game projectile flying to the right, seamless loop, centered, fits within {n}x{n} pixels."
CONE = (". Top-down game spell effect, seamless loop: a cone spray blowing to the right, its tip"
        " a point at the left edge, widening to the right edge, about 60 degrees wide, fits within {n}x{n} pixels.")
BURST = ". Seen from above, one-shot burst, short, centered, fits within {n}x{n} pixels."
# id -> (projectile look, size, impact look, size); no impact look = no burst
SPELLS = {
    "fireball": ("a blazing orange and yellow fireball with a flickering flame tail", 32, None, 0),
    "magic_missile": ("a glowing violet arcane bolt with a short sparkling trail", 24,
                      "a small violet arcane spark burst", 32),
    "frost_jet": ("a gust of freezing breath: wispy semi-transparent white and pale cyan frost mist puffs, swirling icy wind streaks, sparkling ice crystals and snowflakes, soft ragged edges fading out, no solid shape, no outline", 64,
                  None, 0),
    "frost_shard": ("a sharp pale blue ice shard spinning slightly, frosty glints", 24,
                    "pale blue ice shards shattering, frost sparkles", 32),
    "spark": ("a crackling bright yellow electric spark ball with tiny lightning arcs", 24,
              "a yellow electric discharge, crackling lightning sparks", 32),
    "venom_dart": ("a thick glowing green venom dart with a bright poison drop trail", 24,
                   "a green poison splash with toxic droplets", 32),
    "arcane_missiles": ("a bright glowing purple arcane orb missile with a pink comet trail", 24,
                        "a small purple magic sparkle burst", 24),
}
CONES = {"frost_jet"}


def draw(sid: str, burst: bool) -> dict:
    look, n, blook, bn = SPELLS[sid]
    name = f"{sid}_burst" if burst else sid
    path = OUT / f"{name}.png"
    desc = blook + BURST.format(n=bn) if burst else look + (CONE if sid in CONES else BOLT).format(n=n)
    if path.exists():
        strip = path.read_bytes()
        w, h, _ = sheet.read_png(strip)
        meta = {"size": h, "frames": w // h, "fps": sheet.FPS, "loop": not burst}
    else:
        strip, meta = sheet.normalize(*art.vfx(desc, name), loop=not burst)
        path.write_bytes(strip)
    print("ok", name, meta)
    return {"file": path.name, **meta}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:]) or set(SPELLS)
    spells = json.loads(SPELLS_JSON.read_text())
    with ThreadPoolExecutor(6) as pool:
        jobs = {(s, b): pool.submit(draw, s, b) for s in SPELLS if s in only for b in (False, True) if not b or SPELLS[s][2]}
    for d in spells:
        for burst in (False, True):
            job = jobs.get((d["id"], burst))
            if not job:
                continue
            try:
                d["emit"]["body"]["burst_sheet" if burst else "sheet"] = job.result()
                d["bundle"] = "res://assets/spells"
            except Exception as e:  # keep the others
                print("FAILED", d["id"], burst, e)
    SPELLS_JSON.write_text(json.dumps(spells, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
