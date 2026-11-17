# Spell format

A spell is one JSON object. The game never runs code from a spell: it reads
this data, clamps every value (`spell/spell.gd`, `Spell.sanitize`) and prices
it (`Spell.mana_cost`). Anything can produce a spell (the AI forge, level-ups,
hand editing); the result is always safe and balanced by cost.

This file is also sent to the AI as the format reference: keep it accurate.

## Spell

- `name` (string), `description` (string, one sentence, player-facing)
- `element`: `fire` | `ice` | `lightning` | `poison` | `arcane` | `physical` (flavour)
- `color`: `#rrggbb`, main color of the visuals
- `cooldown`: seconds between casts, 0.08 to 5
- `words`: the words written on scrolls so far, oldest first
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
- `speed`: pixels/s, 0 to 1400 (for `orbit` motion: the orbit radius)
- `size`: radius in pixels, 2 to 220
- `lifetime`: seconds, 0.05 to 10
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

## Bundle and art briefs

The forge returns a `.spell` bundle: a zip of `manifest.json` (this spell) and
PNG sprite sheets drawn by PixelLab from art briefs written with the spell:
`icon_brief` on the spell, `look` and `burst` on each body (English, a few
sentences each). The forge then adds `icon_file` and, on bodies, `sheet` /
`burst_sheet` = `{file, w, h, frames, fps, cols}` (frames of w x h, row by row).
The engine draws a sheet when there is one, else the pixel grids below.

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
more mana (max 100 = a full mana bar, which regenerates at 25/s).

Examples: `spell/examples.json`.
