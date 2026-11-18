"""Generate the monster sprites with PixelLab (server/art.py): per kind of
Run.ENEMIES (game/run.gd), and per variant (<kind>_<variant>), seen from
straight above like the octopus mage, its front toward the bottom of the image
(PixMiniMax strikes that way): game/enemy.gd turns it toward where it goes. Its
walk cycle (an idle for the still ones), its death and its special moves; plus the
effects of their attacks.

A monster with a look is drawn in the style (and overhead framing) of the
octopus still tools/octo_still.png, at its size: ~25 choices are kept in
tools/monster_choices/<kind>/, the first becomes base.png (copy another one
over it, delete its animations, and run again to change). One with "from" is
a Pixen edit of that monster's base: its overhead pose kept, which a new
look loses (PixelLab draws faces again). One with "front" (the bosses) is
seen from above but a bit from the front, facing the bottom: its face gives it
weight, and game/enemy.gd mirrors it instead of turning it.

Writes assets/monsters/<kind>/<anim>.png, strips of square frames (the
frame size is the strip height), and assets/monsters/fx/<name>.png (same
format, drawing centered, server/sheet.py). Existing files are kept (delete
one to redo it; delete <kind>/base.png to redraw the monster itself).

Run: python3 tools/make_monsters.py [kind or fx name ...]
"""

import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))
import art  # noqa: E402
import sheet  # noqa: E402

OUT = ROOT / "assets/monsters"
CHOICES = ROOT / "tools/monster_choices"
STILL = ROOT / "tools/octo_still.png"  # 96 pixels
TOP = ("{look}, seen from directly above, bird's-eye view at 90 degrees like the reference: we see the top of its {head}"
       " in the center, its shoulders and arms around it, its feet barely visible, it faces the bottom of the image,"
       " no face visible")
KEEP = ", keep the view from directly above and the same pose"
WALK = "walking forward toward the bottom of the image, seen from directly above, seamless loop"
DEATH = ("dies: collapses and falls down onto the ground, crumbling into a lifeless heap, seen from directly above,"
         " ends lying still")
IDLE = "standing still seen from directly above, breathing gently, seamless loop"
BOW = {"walk": IDLE, "attack": "draws its bow and shoots an arrow toward the bottom of the image"}
CAST = {"walk": IDLE, "attack": "thrusts its hands forward and casts a spell toward the bottom of the image"}
# melee ones: their strike when they touch the mage
CLAW = {"attack": "lunges and slashes with its clawed hands toward the bottom of the image"}
SWORD = {"attack": "swings its sword in a wide slash toward the bottom of the image"}
SHIELDED = CAST | {"death": "dies: its magic shield bubble shatters and vanishes, then it " + DEATH[6:]}
SHIELD = "surround it with a big round translucent glowing magic shield bubble" + KEEP
DARK = "dark heroic fantasy game undead graveyard monster, full body, menacing, "
MAGE = "a skeleton mage in a tattered dark robe"
# look (kind or kind_variant) -> (size, {"look": (what, its head)} or {"from": (look, change)}, {anim: action});
# "walk" defaults to WALK, "death" (game/enemy.gd Corpse) to DEATH.
MONSTERS = {
    "skeleton": (48, {"look": ("a plain undead skeleton, empty handed", "bare white skull")}, CLAW),
    "archer": (48, {"look": ("a skeleton archer with a brown scarf, a wooden bow held in front of it", "bare white skull")}, BOW),
    "marksman": (48, {"from": ("archer", "make it a marksman: a longbow and a brown hood over the skull" + KEEP)}, BOW),
    "imp": (48, {"look": ("a small red imp with clawed hands, a pointy tail behind it", "red head with two tiny horns")},
            {"walk": "scampering fast toward the bottom of the image, seen from directly above, seamless loop"} | CLAW),
    "zombie": (48, {"look": ("a grey skinned shambling zombie in torn rags, arms reaching forward", "bald grey head")},
               {"walk": "shambling slowly toward the bottom of the image, seen from directly above, seamless loop",
                "attack": "lunges forward and grabs with both arms toward the bottom of the image"}),
    "rotting_zombie": (48, {"from": ("zombie", "make it rotting, oozing green, with a green aura of buzzing flies around it" + KEEP)},
                       {"walk": "shambling slowly toward the bottom of the image, flies buzzing around, seen from directly above, seamless loop",
                        "attack": "lunges forward and grabs with both arms toward the bottom of the image, flies buzzing around"}),
    "skeletal_warrior": (48, {"look": ("an undead skeleton warrior with iron gauntlets and a rusty sword, no helmet", "bare white skull")}, SWORD),
    "skeletal_warrior_helmet": (48, {"from": ("skeletal_warrior", "put a round iron helmet on its skull" + KEEP)}, SWORD),
    "skeletal_knight": (48, {"look": ("a skeleton knight with an iron chestplate and iron pauldrons, bare bony hands, a sword",
                                      "round iron helmet")}, SWORD),
    "skeletal_knight_gauntlets": (48, {"from": ("skeletal_knight", "give it iron gauntlets on its hands" + KEEP)}, SWORD),
    "wraith": (48, {"look": ("a pure white ghostly wraith with a tattered cloak and no legs, glowing icy wisps", "white tattered hood")},
               {"walk": "floating toward the bottom of the image, cloak fluttering, seen from directly above, seamless loop",
                "attack": "lashes out with its icy ghostly claws toward the bottom of the image, freezing wisps bursting",
                "death": "dies: shrieks, its cloak unravels and it fades away into icy wisps, seen from directly above"}),
    "putrid_archer": (48, {"from": ("archer", "put a brown hood on its skull, dripping green poison" + KEEP)}, BOW),
    "burning_archer": (48, {"from": ("archer", "engulf it in orange flames" + KEEP)}, BOW),
    "burning_skeleton": (48, {"from": ("skeleton", "engulf it in orange flames" + KEEP)}, CLAW),
    "fire_mage": (48, {"look": (MAGE + ", its two hands on fire", "dark pointed hood")}, CAST),
    "fire_mage_shield": (48, {"from": ("fire_mage", SHIELD)}, SHIELDED),
    "poison_mage": (48, {"from": ("fire_mage", "replace the fire in its hands with glowing green balls" + KEEP)}, CAST),
    "poison_mage_shield": (48, {"from": ("poison_mage", SHIELD)}, SHIELDED),
    "frost_mage": (48, {"from": ("fire_mage", "replace the fire in its hands with glowing icy blue balls" + KEEP)}, CAST),
    "frost_mage_shield": (48, {"from": ("frost_mage", SHIELD)}, SHIELDED),
    "lightning_mage": (48, {"from": ("fire_mage", "replace the fire in its hands with crackling white balls of lightning" + KEEP)}, CAST),
    "lightning_mage_shield": (48, {"from": ("lightning_mage", SHIELD)}, SHIELDED),
    "boss": (96, {"front": "a towering lich king, a skeleton in ornate violet robes with a golden crown, holding a glowing staff,"
                           " huge imposing boss"}, {
        "walk": "floating toward the viewer, robes flowing, seamless loop",
        "summon": "raises its glowing staff, violet necrotic magic swirls around it, summoning",
        "death": "staggers in agony, cracks of blinding violet light burst out of its body, about to explode"}),
    "death_knight": (96, {"front": "a huge undead death knight in black spiked plate armor and spiked helmet,"
                                   " a frost glowing greatsword, huge imposing boss"}, {
        "windup": "raises its greatsword and roars, bracing to charge toward the viewer",
        "slam": "slams its greatsword into the ground, an icy shockwave bursting around it",
        "death": "staggers and drops to its knees, blinding icy blue light bursting through cracks in its armor, about to explode"}),
    "abomination": (96, {"front": "a giant bloated undead flesh abomination stitched from corpses, green ooze dripping,"
                                  " small stitched head sunk between huge shoulders, huge imposing boss"}, {
        "walk": "lumbering heavily toward the viewer, seamless loop",
        "summon": "its belly bursts open and small red imps crawl out",
        "attack": "rears back and spews a wide spray of green acid toward the viewer",
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


def _style(size: int) -> bytes:
    """The octopus still at `size` pixels (96, or halved)."""
    png = STILL.read_bytes()
    if size == 96:
        return png
    w, _, px = sheet.read_png(png)
    k = w // size
    return sheet.write_png(size, size, b"".join(bytes(px[(k * y * w + k * x) * 4:(k * y * w + k * x) * 4 + 4])
                                                for y in range(size) for x in range(size)))


def monster(kind: str) -> None:
    size, how, anims = MONSTERS[kind]
    d = OUT / kind
    d.mkdir(parents=True, exist_ok=True)
    base = d / "base.png"
    if not base.exists():
        if "front" in how:
            base.write_bytes(art.front(DARK + how["front"], size))
        elif "from" in how:
            src = OUT / how["from"][0] / "base.png"
            for _ in range(180):  # drawn by another job of this run
                if src.exists():
                    break
                time.sleep(10)
            base.write_bytes(art.edit(src.read_bytes(), how["from"][1]))
        else:
            what, head = how["look"]
            choices = art.styled(_style(size), TOP.format(look=what, head=head))
            (CHOICES / kind).mkdir(parents=True, exist_ok=True)
            for i, png in enumerate(choices):
                (CHOICES / kind / f"{i}.png").write_bytes(png)
            base.write_bytes(choices[0])
    for anim, action in ({"walk": WALK, "death": DEATH} | anims).items():
        path = d / f"{anim}.png"
        if not path.exists():
            path.write_bytes(_strip(art.animate(base.read_bytes(), action, 8)))
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
    with ThreadPoolExecutor(10) as pool:  # PixelLab Tier 2: 11 concurrent jobs at most
        for job, arg in todo:
            pool.submit(_safe, job, arg)


if __name__ == "__main__":
    main()
