"""Generate the monster sprites with PixelLab (server/art.py): per kind of
Run.ENEMIES (game/run.gd) a side view facing right, its walk cycle and its
special moves; plus the effects of their attacks.

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
STYLE = "dark heroic fantasy game monster, full body, side view facing right, menacing"
BOSS = "huge imposing boss monster, highly detailed, ornate, " + STYLE
WALK = "walking forward, looping walk cycle"
# kind -> (canvas size, look, {anim: action}); "walk" defaults to WALK.
MONSTERS = {
    "melee": (48, "a green goblin grunt with a rusty club", {}),
    "fast": (40, "a small lean yellow imp with bat wings and claws", {"walk": "flapping its wings, darting forward"}),
    "ranged": (48, "a small goblin caster in a cyan hood holding a glowing cyan wand", {}),
    "bomber": (48, "a round orange goblin sapper hugging a big black bomb with a fuse", {
        "fuse": "the bomb fuse burns with bright sparks, the goblin shakes and swells, about to explode"}),
    "slime": (48, "a dome-shaped blob of translucent green slime jelly, not humanoid, no arms, no legs, two eyes", {"walk": "bouncing forward, squashing and stretching"}),
    "slimelet": (32, "a tiny dome-shaped blob of translucent light green slime jelly, not humanoid, no arms, no legs, two eyes", {"walk": "bouncing forward, squashing and stretching"}),
    "brute": (64, "a hulking brown ogre brute with huge fists and a leather harness", {
        "windup": "lowers its head and paws the ground, snorting, about to charge"}),
    "stalker": (48, "a sleek purple shadow panther with glowing eyes", {"walk": "prowling forward, stalking"}),
    "spitter": (48, "an olive green toad with a swollen poison throat sac", {"walk": "hopping forward"}),
    "shaman": (48, "a teal skinned goblin shaman with a bone staff and a feather headdress", {
        "heal": "raises its staff high, green healing light glows around it"}),
    "wraith": (48, "a pale grey-blue hooded wraith with a tattered cloak and no legs", {
        "walk": "floating forward, cloak fluttering", "blink": "dissolves into grey smoke and vanishes"}),
    "necromancer": (48, "a skeleton necromancer in deep purple robes holding a skull staff", {
        "summon": "raises its skull staff, dark purple magic swirls, summoning"}),
    "sorcerer": (48, "a horned demon sorcerer in pink robes with glowing pink hands", {}),
    "golem": (64, "a massive grey stone golem with glowing blue runes", {"walk": "stomping forward heavily"}),
    "boss": (96, "a towering lich king, a skeleton in ornate violet robes with a crown and a glowing staff", {
        "walk": "floating forward, robes flowing",
        "summon": "raises its glowing staff high, violet necrotic magic swirls around it, summoning"}),
    "warlord": (96, "a huge orc warlord in red spiked plate armor wielding a giant axe", {
        "windup": "raises its giant axe and roars, bracing to charge"}),
    "broodmother": (96, "a giant bloated olive green spider broodmother with a glowing egg sac", {
        "walk": "crawling forward on its eight legs",
        "summon": "rears up, its egg sac pulses and spawns small slimes"}),
}
# Effects of the attacks (game/enemy.gd Shot and Zone), name -> brief.
FX = {
    "bolt": "a small glowing crimson magic orb projectile with a short dark trail, flying right, looping",
    "acid": "a small blob of green acid spit projectile with dripping trail, flying right, looping",
    "explosion": "a fiery explosion burst, orange and yellow flames and black smoke, seen from above",
    "shockwave": "a ground slam shockwave, a ring of dust and cracked stone bursting outward, seen from above",
    "poison": "a bubbling toxic green poison puddle on the ground, seen from above, looping",
    "heal": "a burst of green healing light and rising sparkles in a circle, seen from above",
    "blink": "a puff of grey ghostly smoke swirling and fading",
    "summon": "a dark purple summoning portal circle with runes opening on the ground, seen from above",
}
LOOPING = {"bolt", "acid", "poison"}


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
