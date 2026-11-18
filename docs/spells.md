# Spell format

A spell is one JSON object. The game never runs code from a spell: it reads
this data, clamps every value (`spell/spell.gd`, `Spell.sanitize`) and prices
it (`Spell.mana_cost`). Anything can produce a spell (the AI forge, level-ups,
hand editing); the result is always safe and balanced by cost.

This file is also sent to the AI as the format reference: keep it accurate.

## Spell

- `name` (string), `description` (string, one sentence, player-facing, in English), `description_fr` (the same sentence in French; base spells leave it out and are translated by `locale/fr.po`)
- `element`: `fire` | `ice` | `lightning` | `poison` | `arcane` | `physical` (flavour,
  and the texture of the spell's sounds, synthesized by the engine from the
  element and each body's shape, size and speed: `spell/spell_sound.gd`)
- `color`: `#rrggbb`, main color of the visuals
- `cooldown`: seconds between casts, 0.08 to 5
- `words`: the words written on scrolls so far, oldest first
- `origin`: set by the forge, the name of the base spell it was forged from
- `emit`: an **Emit**, what happens when the spell is cast
- `palette`: up to 8 `#rrggbb` colors used by all the pixel art of the spell
- `icon`: **pixel grid**, up to 24x24, the spell's icon

## Emit: how bodies are launched

- `pattern`: `aim` (toward the aim, fanned over `spread`), `radial` (evenly in
  a full circle), `random` (random angle within `spread`), `nearest` (toward
  the nearest enemy, fanned over `spread`)
- `count`: bodies launched, 1 to 16
- `spread`: degrees, 0 to 360
- `burst_delay`: seconds between consecutive bodies (0 = all at once), up to 0.5
- `body`: a **Body**

## Body: one launched thing

- `shape`: `bolt` (hits enemies it touches) or `zone` (a lingering area that
  acts only through `on_tick` / `on_expire`; give it `speed` 0 to stay put)
  or a channeled shape, recast every `cooldown` while the button is held (each
  cast is one tick and costs mana; give it `lifetime` = `cooldown`). Both stay
  on the caster and apply `on_hit` once per cast: `beam` (an electric arc that
  grips the nearest enemy within `speed` px and `angle`, the same one while it
  stays there) or `cone` (every enemy within `speed` px and `angle`)
- `speed`: pixels/s, 0 to 1400 (for `orbit` motion: the orbit radius)
- `size`: radius in pixels, 2 to 220
- `lifetime`: seconds, 0.05 to 10
- `angle`: degrees, 0 to 180, full width of a `beam`'s or `cone`'s reach
- `pierce`: extra enemies a bolt goes through, 0 to 20
- `bounce`: times a bolt jumps to the next nearest enemy, 0 to 10
- `motion`: list of `{type, strength}` (strength -10 to 10):
  `homing` (steers to enemies; a homing body ignores `lifetime`: it flies until
  it hits, or leaves the map while no enemy is left), `wave` (zigzags), `accelerate` (negative
  slows down), `boomerang` (returns to the caster), `orbit` (circles the caster)
- `on_hit`: **Effects** on each enemy a bolt touches
- `on_expire`: **Effects** where the body ends (lifetime over or stopped)
- `tick_interval`: seconds, 0.1 to 5; `on_tick`: **Effects** applied every interval
- `sprite`: 1 to 4 animation frames (**pixel grids**, up to 16x16), played at
  8 frames/s. A bolt sprite faces right (it is rotated to its direction); a
  zone sprite is drawn as is, stretched over the zone.
- `particle`: **pixel grid** up to 8x8, the particle trailing the body

## Bundle format (version 1)

The forge returns a `.spell` bundle, a zip:

- `manifest.json`: this spell, plus `"format": 1`.
- `icon.png`: 32x32 RGBA, drawing centered. Named by the spell's `icon_file`.
- One PNG per animated **sheet**, named by a body's `sheet` (its looping
  animation) or `burst_sheet` (its one-shot impact, played where it expires):
  `{file, size, frames, fps, loop}`.

Every sheet follows the same convention, so the engine loads and plays them
all the same way:

- one horizontal strip of `frames` square frames of `size` x `size` pixels
  (PNG `size * frames` x `size`), `size` a multiple of 8, RGBA, transparent;
- the drawing centered in each frame: the engine anchors sheets on the body's
  position; bolt sheets face right and are rotated to the body's direction;
- 12 frames per second, at least 2 different frames;
- drawn at the art scale (one art pixel = 3 screen pixels), never resized.

The forge enforces it (`server/sheet.py` normalizes what PixelLab draws and
rejects still drawings); `python3 server/check_bundle.py file.spell` checks a
bundle; the game drops a sheet that does not match its PNG and falls back to
the body's pixel grids, which it turns into the same strip format.

Art briefs: with the spell, write in English `icon_brief` on the spell and
`look` (the moving body) and `burst` (its impact) on each body. PixelLab
draws the first 2 bodies and the main body's impact from them.

## Pixel art

Everything is pixel art, scaled up without blur. A **pixel grid** is a list of
strings of the same length, one per row, top to bottom: `.` is transparent,
`0` to `7` is a color of the spell's `palette`. Draw with care: a clear
silhouette, a dark outline or darker edge, highlights from the top-left,
2 to 5 colors per sprite. Each body of the spell (including the ones of
sub-casts) gets its own sprite matching what it is.

Screen size is 1280x720, an enemy has 20 HP at the start and a radius of 12.

## Effects

Each effect has a `type`. `radius` (0 to 300) makes it hit every enemy in that
area around the body; with radius 0 it hits the touched enemy (or, for a zone,
every enemy inside the zone).

- `damage`: `amount` (0 to 500)
- `status`: `status` = `burn` | `poison` (damage per second = power) |
  `slow` | `freeze` | `stun`; `power` (0 to 100), `duration` (0.1 to 10)
- `knockback`: `force` (-800 to 800, negative pulls toward the body)
- `heal`: heals the caster by `amount` (0 to 100)
- `cast`: `emit` = an **Emit** launched from where the effect happens. This is
  how spells split, explode into shards, leave zones behind... Nested at most
  3 levels deep.

## Balance

Mana cost is computed from the spell's damage potential (count, pierce,
bounce, ticks, areas, sub-casts). A stronger spell is not refused, it costs
more mana (max 100 = a full mana bar, which regenerates at 25/s). In a run,
every level-up upgrade but Thrift also taxes the cost +10 % (`Run.UPGRADE_TAX`).

Examples: `spell/examples.json`.
