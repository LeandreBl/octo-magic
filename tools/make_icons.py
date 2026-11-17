"""Generate the UI icons with PixelLab (server/art.py): one per base spell
(game/spells.json) and per shop item (game/profile.gd ITEMS), plus gold.
Writes assets/icons/<id>.png; existing files are kept (delete one to redo it).

Run: python3 tools/make_icons.py [id ...]
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/icons"
STYLE = ("fantasy game inventory icon, a single object or symbol, no character, no person,"
         " no creature, no scenery, transparent background, centered, bold readable shape")
# English art briefs (an object or symbol), as the forge's icon_brief.
SPELLS = {
    "fire_bolt": "a blazing fire arrow streaking diagonally, orange and yellow flames",
    "frost_shard": "a sharp pale blue ice crystal shard, frosty glints",
    "spark": "a bright yellow electric spark burst with small crackling lightning arcs",
    "venom_dart": "a green poisoned dart dripping venom",
    "arcane_missiles": "three glowing violet magic arrows flying in parallel, arcane energy trails",
    "fire_nova": "a ring of fire flames bursting outward in a circle",
    "frost_ring": "a circle of ice spikes and snowflakes, pale cyan",
    "toxic_cloud": "a cracked glass potion flask releasing a green toxic cloud",
    "thunder_chain": "a zigzag yellow lightning bolt chained in several links",
    "arcane_orbit": "two glowing purple orbs orbiting a small rune",
    "meteor_rain": "a flaming meteor falling with a fiery tail",
    "blizzard": "a swirling snowstorm with snowflakes and ice wind",
    "storm": "a dark storm cloud shooting several lightning bolts",
    "plague": "a green skull surrounded by a crown of poison darts",
    "black_hole": "a swirling black hole vortex with a violet glowing rim",
}


def jobs() -> dict[str, str]:
    out = {k: f"{STYLE}: {v}" for k, v in SPELLS.items()}
    profile = (ROOT / "game/profile.gd").read_text()
    for id_, kind, color in re.findall(r'"(\w+)": \{"kind": "(\w+)", "name": "[^"]+", "price": \d+, "color": "([^"]*)"', profile):
        if color:
            what = {"staff": "a wooden wizard staff with a gem on top", "robe": "an empty long wizard robe garment on a hanger, nobody wearing it",
                    "ring": "a magic ring with a gem"}[kind]
            out[id_] = f"{STYLE}: {what}, main color {color}"
    out["gold"] = f"{STYLE}: a small stack of shiny gold coins"
    out["scroll"] = f"{STYLE}: a blank rolled parchment scroll with a red wax seal"
    return out


def icon(desc: str) -> bytes:
    """32x32 PNG, the drawing centered (server/sheet.py)."""
    return sheet.normalize_icon(art.icon(desc))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])  # optional: ids to make
    for id_, desc in jobs().items():
        if only and id_ not in only:
            continue
        path = OUT / f"{id_}.png"
        if path.exists():
            continue
        try:
            path.write_bytes(icon(desc))
            print("ok", id_)
        except Exception as e:  # keep going: one failure must not lose the rest
            print("FAILED", id_, e)


if __name__ == "__main__":
    main()
