"""Generate the monster sprites with PixelLab (server/art.py): per kind of
Run.ENEMIES (game/run.gd), and per variant (<kind>_<variant>), a side view
facing right, its walk cycle (an idle for the still ones) and its special
moves; plus the effects of their attacks.

Writes assets/monsters/<kind>/<anim>.png, strips of square frames (the
frame size is the strip height), and assets/monsters/fx/<name>.png (same
format, drawing centered, server/sheet.py). Existing files are kept (delete
one to redo it; delete <kind>/base.png to redraw the monster itself).

Run: python3 tools/make_monsters.py [kind or fx name ...]
"""

import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/monsters"
STYLE = "dark heroic fantasy game undead graveyard monster, full body, side view facing right, menacing"
BOSS = "huge imposing boss monster, highly detailed, ornate, " + STYLE
WALK = "walking forward, looping walk cycle"
IDLE = "standing still, breathing, looping idle"
BOW = {"walk": IDLE, "attack": "draws its bow and shoots an arrow to the right"}
CAST = {"walk": IDLE, "attack": "thrusts its hands forward and casts a spell to the right"}
MAGE = "a skeleton mage in a tattered dark robe"
# look (kind or kind_variant) -> (canvas size, look, {anim: action}); "walk" defaults to WALK.
MONSTERS = {
    "skeleton": (48, "a plain skeleton, bare bones", {}),
    "archer": (48, "a skeleton archer with a bow and a brown scarf", BOW),
    "marksman": (48, "a skeleton marksman with a longbow and a brown hood", BOW),
    "imp": (40, "a small red imp with tiny horns, claws and a pointy tail", {"walk": "scampering forward fast"}),
    "zombie": (48, "a grey skinned shambling zombie in torn rags", {"walk": "shambling forward slowly"}),
    "rotting_zombie": (48, "a grey skinned rotting zombie oozing green, surrounded by a green aura of buzzing flies",
                       {"walk": "shambling forward slowly, flies buzzing around"}),
    "skeletal_warrior": (48, "an undead skeleton warrior, bare white skull and bony ribs, iron gauntlets, a rusty sword, no helmet", {}),
    "skeletal_warrior_helmet": (48, "an undead skeleton warrior, white skull face under an iron helmet, bony ribs, iron gauntlets, a rusty sword", {}),
    "skeletal_knight": (48, "a skeleton knight with an iron helmet and an iron chestplate, bare bony hands, a sword", {}),
    "skeletal_knight_gauntlets": (48, "an undead skeleton knight, white skull face under an iron helmet, an iron chestplate, iron gauntlets, bony legs, a sword", {}),
    "wraith": (48, "a pure white ghostly wraith with a tattered cloak and no legs, glowing icy eyes",
               {"walk": "floating forward, cloak fluttering"}),
    "putrid_archer": (48, "a skeleton archer in a brown hood dripping green poison, with a bow", BOW),
    "burning_archer": (48, "a skeleton archer engulfed in orange flames, with a bow", BOW),
    "burning_skeleton": (48, "a skeleton engulfed in orange flames", {}),
    "fire_mage": (48, MAGE + ", its hands on fire", CAST),
    "fire_mage_shield": (48, MAGE + ", its hands on fire, inside a translucent glowing magic shield bubble", CAST),
    "poison_mage": (48, MAGE + ", glowing green balls in its hands", CAST),
    "poison_mage_shield": (48, MAGE + ", glowing green balls in its hands, inside a translucent glowing magic shield bubble", CAST),
    "frost_mage": (48, MAGE + ", glowing blue balls in its hands", CAST),
    "frost_mage_shield": (48, MAGE + ", glowing blue balls in its hands, inside a translucent glowing magic shield bubble", CAST),
    "lightning_mage": (48, MAGE + ", crackling white balls of lightning in its hands", CAST),
    "lightning_mage_shield": (48, MAGE + ", crackling white balls of lightning in its hands, surrounded by a big round translucent white magic shield bubble", CAST),
    "boss": (96, "a towering lich king, a skeleton in ornate violet robes with a crown and a glowing staff", {
        "walk": "floating forward, robes flowing",
        "summon": "raises its glowing staff high, violet necrotic magic swirls around it, summoning",
        "death": "staggers in agony, cracks of blinding violet light burst out of its body, about to explode"}),
    "death_knight": (96, "a huge undead death knight, a skeleton in black spiked plate armor with a frost glowing greatsword", {
        "windup": "raises its greatsword and roars, bracing to charge",
        "death": "staggers and drops to its knees, blinding icy blue light bursting through cracks in its armor, about to explode"}),
    "abomination": (96, "a giant bloated undead flesh abomination stitched from corpses, green ooze dripping", {
        "walk": "lumbering forward heavily",
        "summon": "its belly bursts open and small red imps crawl out",
        "death": "swells up grotesquely, bloating bigger and bigger, glowing green light bursting through its seams, about to burst"}),
}
# Effects of the attacks (game/enemy.gd Shot and Zone, Run.ENEMIES "shot"), name -> brief.
FX = {
    "bolt": "a small glowing crimson magic orb projectile with a short dark trail, flying right, looping",
    "acid": "a small blob of green acid spit projectile with dripping trail, flying right, looping",
    "arrow": "a big long wooden arrow projectile with a bone arrowhead and grey feathers, horizontal, filling the frame, flying right, looping",
    "poison_arrow": "a big long wooden arrow projectile with a green glowing poison arrowhead dripping toxic green drops, horizontal, filling the frame, flying right, looping",
    "fire_arrow": "a flaming arrow trailing fire flying right, looping",
    "fireball": "a fireball projectile with a trail of flames flying right, looping",
    "poison_orb": "a glowing toxic green orb projectile with a bubbling trail flying right, looping",
    "frost_orb": "a glowing icy blue orb projectile with frost shards trail flying right, looping",
    "spark": "a crackling white lightning ball projectile with electric arcs flying right, looping",
    "shockwave": "a ground slam shockwave, a ring of dust and cracked stone bursting outward, seen from above",
    "poison": "a bubbling toxic green poison puddle on the ground, seen from above, looping",
    "summon": "a dark purple summoning portal circle with runes opening on the ground, seen from above",
    # a boss's death (game/boss_death.gd): blasts popping on its body, then the big one
    "boss_blast": "a fiery explosion burst, an orange and yellow fireball with a bright white core puffing into black smoke, one-shot",
    "boss_explosion": "a huge spectacular explosion, a massive fireball blast with a bright white core, a shockwave ring,"
                      " flying burning debris and sparks, billowing dark smoke, seen from above, one-shot",
}
LOOPING = {"bolt", "acid", "poison", "arrow", "poison_arrow", "fire_arrow", "fireball", "poison_orb", "frost_orb", "spark"}


def _strip(frames: list[bytes]) -> bytes:
    """Same-size PNG frames -> one horizontal strip."""
    imgs = [sheet.read_png(f) for f in frames]
    w, h = imgs[0][0], imgs[0][1]
    n = len(imgs)
    out = bytearray(w * n * h * 4)
    for i, (_, _, px) in enumerate(imgs):
        for y in range(h):
            out[(y * w * n + i * w) * 4:(y * w * n + i * w + w) * 4] = px[y * w * 4:(y + 1) * w * 4]
    return sheet.write_png(w * n, h, out)


def monster(kind: str) -> None:
    size, look, anims = MONSTERS[kind]
    d = OUT / kind
    d.mkdir(parents=True, exist_ok=True)
    base = d / "base.png"
    if not base.exists():
        base.write_bytes(art.sprite(f"{BOSS if size >= 96 else STYLE}, {look}", size,
                                    "highly detailed" if size >= 96 else "medium detail"))
    for anim, action in ({"walk": WALK} | anims).items():
        path = d / f"{anim}.png"
        if not path.exists():
            frames = art.animate(base.read_bytes(), action, 8)
            path.write_bytes(_strip(frames[-8:]))  # without the reference frame
        print("ok", kind, anim)


def fx(name: str) -> None:
    png, meta = art.vfx(FX[name], name)
    strip, _ = sheet.normalize(png, meta, name in LOOPING)
    (OUT / "fx" / f"{name}.png").write_bytes(strip)
    print("ok fx", name)


def _safe(job, arg) -> None:
    try:
        job(arg)
    except Exception as e:  # keep going: one failure must not lose the rest
        print("FAILED", arg, e)


def main() -> None:
    (OUT / "fx").mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    todo = [(monster, k) for k in MONSTERS if not only or k in only]
    todo += [(fx, n) for n in FX if (not only or n in only) and not (OUT / "fx" / f"{n}.png").exists()]
    with ThreadPoolExecutor(6) as pool:
        for job, arg in todo:
            pool.submit(_safe, job, arg)


if __name__ == "__main__":
    main()
