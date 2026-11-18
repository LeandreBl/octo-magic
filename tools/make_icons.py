"""Generate the UI icons with PixelLab (server/art.py): one per base spell
(game/spells.json) and per shop item (game/profile.gd ITEMS), plus gold.
Writes assets/icons/<id>.png; existing files are kept (delete one to redo it).

Run: python3 tools/make_icons.py [id ...]
"""

import json
import re
import subprocess
import sys
import tempfile
import urllib.error
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
    "fireball": "a big blazing ball of fire with a short flaming tail, orange and yellow",
    "lightning": "a single bright blue-white jagged lightning bolt striking diagonally, crackling electric glow",
    "magic_missile": "a glowing violet magic arrowhead curving toward a small target rune",
    "frost_jet": "a wide spray of freezing icy wind and snowflakes blowing out sideways from a glowing frost rune, pale cyan, not food",
    "frost_shard": "a sharp pale blue ice crystal shard, frosty glints",
    "spark": "a bright yellow electric spark burst with small crackling lightning arcs",
    "venom_dart": "a green poisoned dart dripping venom",
    "arcane_missiles": "three glowing violet magic arrows flying in parallel, arcane energy trails",
    "fire_nova": "a ring of fire flames bursting outward in a circle",
    # used by the website only (web/): stat and element icons
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


# Grimoire skill icons (game/upgrades.gd LIST), as up_<id>; others used by the shop perks.
UPGRADES = {
    "damage": "a glowing red fist-shaped rune of raw power with sparks",
    "cooldown": "a small golden hourglass with glowing blue sand",
    "mana": "a blue mana potion flask with a downward arrow rune",
    "toughness": "a red heart wrapped in a sturdy iron band",
    "reservoir": "a large round blue mana flask filled to the brim, glowing",
    "haste": "a glowing wizard staff tip shooting rapid bursts of blue sparks with speed lines",
    "flow": "a swirling stream of glowing blue mana droplets in a spiral",
    "fleetness": "a winged boot with a speed trail",
    "fortune": "a four-leaf clover over a shiny gold coin",
    "insight": "a glowing open eye inside a golden star",
    "magnetism": "a red and silver horseshoe magnet pulling small gold sparks",
    "ward": "a round silver shield with a glowing blue protective rune",
    "precision": "a red bullseye target pierced dead center by a glowing arrow",
    "thrift": "a small blue mana crystal on a cracked open coin purse, a few blue mana drops saved inside",
    "inspiration": "a fan of four glowing magic cards held open, the fourth one shining gold",
    "channeling": "a glowing blue mana rune circle on the ground with blue mana streams spiraling up into its center",
    "antidote": "a small round glass vial of bright golden antidote liquid with a cork, a crossed-out green poison drop rune on it",
    "ether_charge": "a glowing blue-white ether crystal crackling with a small lightning charge, a mana drop rune inside",
    "harden": "a solid pale blue ice cube with sharp frosty edges and white frost cracks, cold blue glow",
    "more_missiles": "a single glowing violet magic orb splitting into a wide fan of five small violet sparks, a plus rune above it",
    "stun": "a small round yellow star burst with dizzy swirling stars and tiny lightning sparks circling it, stunned symbol",
    "chaining": "a crackling blue-white lightning arc linking three small glowing orbs in a zigzag chain",
    "hurricane": "a swirling pale cyan whirlwind of icy wind gusts and snowflakes, spiraling outward",
    "chill_wind": "a small frozen hourglass covered in frost and icicles, its pale blue sand slowed to a trickle, snowflakes around it",
    "cone_of_ice": "a pale blue and white triangular cone of sharp ice crystals fanning out to the right, cold frosty colors only, blue cyan white, no fire, no orange",
    "embers": "a small heap of glowing orange embers and hot coals with tiny flames and rising sparks",
    "immolation": "a burning wooden effigy totem engulfed in tall orange and red flames, embers rising",
    "fireproof": "a round red and gold shield deflecting orange flames, a glowing protective rune in its center",
}


SHINE = ("a quick bright golden sparkle glint burst, small yellow and white star twinkles popping out from the center,"
         " shiny gold coin shine. Seen from above, one-shot burst, short, centered, fits within 32x32 pixels.")


def jobs() -> dict[str, str]:
    out = {k: f"{STYLE}: {v}" for k, v in SPELLS.items()}
    out |= {f"up_{k}": f"{STYLE}: {v}" for k, v in UPGRADES.items()}
    profile = (ROOT / "game/profile.gd").read_text()
    for id_, kind, color in re.findall(r'"(\w+)": \{"kind": "(\w+)", "name": "[^"]+", "price": \d+, "color": "([^"]*)"', profile):
        if color:
            what = {"staff": "a wooden wizard staff with a gem on top", "robe": "an empty long wizard robe garment on a hanger, nobody wearing it",
                    "ring": "a magic ring with a gem"}[kind]
            out[id_] = f"{STYLE}: {what}, main color {color}"
    out["gold"] = f"{STYLE}: a small stack of shiny gold coins"
    # Not STYLE (fantasy object): the account screen's Google login button.
    out["google"] = ("pixel art Google logo: a bold capital letter G made of four colored segments,"
                     " blue right bar, red top, yellow bottom left, green bottom, on transparent background")
    # Floor drops (game/pickup.gd), as drop_<kind>.
    drop = "pixel art game pickup lying on the ground, seen from above at an angle, transparent background, centered"
    # Gold heaps grow with the gold they hold (game/pickup.gd GOLD_TIERS).
    out["drop_gold_1"] = f"{STYLE}: one single shiny gold coin lying flat, yellow metal disc"
    out["drop_gold_2"] = f"{STYLE}: two or three shiny gold coins slightly overlapping, yellow metal discs"
    out["drop_gold"] = f"{STYLE}: a small heap of gold coins, yellow shiny metal discs, treasure loot"
    out["drop_gold_hoard"] = f"{STYLE}: a big overflowing treasure pile of many gold coins with a few red and blue gems, shiny loot hoard"
    orb = ("pixel art game pickup, a single perfectly round glossy magic glass orb sphere, transparent background, centered,"
           " no frame, no ring, no base, no outline ring")
    out["drop_mana"] = f"{orb}: beautiful glowing sapphire blue mana orb, bright cyan core light inside, deep blue edges, small white specular highlight top-left, soft blue aura"
    out["drop_life"] = f"{orb}: beautiful glowing ruby red life orb, bright scarlet core light inside, deep crimson edges, small white specular highlight top-left, soft red aura"
    out["scroll"] = f"{STYLE}: a blank rolled parchment scroll with a red wax seal"
    # Grimoires (red: hero stats, blue: spell stats): picked up, they open the upgrade choice.
    out["drop_grimoire_hero"] = f"{drop}: a small closed spellbook grimoire with a crimson red leather cover, gold corners and a glowing gold rune on the cover"
    out["drop_grimoire_spell"] = f"{drop}: a small closed spellbook grimoire with a deep blue leather cover, silver corners and a glowing cyan rune on the cover"
    out["drop_quad"] = f"{drop}: a glowing violet power-up rune stone carved with a big number 4, crackling purple energy"
    return out


def icon(desc: str) -> bytes:
    """ICON x ICON PNG, the drawing centered (server/sheet.py); through
    ChatGPT (codex_icon) once PixelLab is out of credits."""
    try:
        return sheet.normalize_icon(art.icon(desc, sheet.ICON))
    except urllib.error.HTTPError as e:
        if e.code != 402:
            raise
        return codex_icon(desc)


def codex_icon(desc: str) -> bytes:
    """The Codex CLI's image generation (the ChatGPT plan: `codex login`), in
    the look of two existing icons, then boxed down to 32x32 with a black
    outline (ImageMagick `convert`)."""
    gen = Path.home() / ".codex/generated_images"
    before = set(gen.rglob("*.png"))
    refs = ",".join(str(OUT / f) for f in ("up_flow.png", "up_ward.png"))
    prompt = ("Use your image generation tool, do not draw with code and do not write any file. Generate ONE"
              " pixel-art game icon in the style of the attached reference icons (chunky pixels, black outline,"
              f" transparent background, centered, bold readable shape, few details). {desc}")
    subprocess.run(["codex", "exec", "--skip-git-repo-check", "-s", "read-only", "-i", refs, "-"],
                   input=prompt, text=True, check=True, capture_output=True, timeout=600)
    new = sorted(set(gen.rglob("*.png")) - before, key=lambda p: p.stat().st_mtime)
    if not new:
        raise RuntimeError("codex generated no image")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "icon.png"
        subprocess.run(["convert", str(new[-1]), "-trim", "+repage", "-filter", "Box", "-resize", "30x30",
                        "-channel", "A", "-threshold", "50%", "+channel", "-background", "none",
                        "-gravity", "center", "-extent", "32x32",
                        "(", "+clone", "-alpha", "extract", "-morphology", "Dilate", "Diamond:1",
                        "-background", "black", "-alpha", "shape", ")", "+swap", "-compose", "over", "-composite",
                        "-channel", "A", "-threshold", "50%", "+channel", f"PNG32:{out}"], check=True)
        return out.read_bytes()


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
    # The glint of a gold heap once it lands (game/pickup.gd SHINE): a one-shot strip.
    shine = OUT / "drop_gold_shine.png"
    if not shine.exists() and (not only or "drop_gold_shine" in only):
        strip, meta = sheet.normalize(*art.vfx(SHINE, "drop_gold_shine"), loop=False)
        shine.write_bytes(strip)
        print("ok drop_gold_shine", meta)


if __name__ == "__main__":
    main()
