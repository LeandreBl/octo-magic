# octo-magic
Create, combine and cast spells to conquer a dungeon.

## Run

- Game: open the folder in Godot 4.7 (`godot --path .`).
- Spell forge (needed only to write on scrolls):
  `ANTHROPIC_API_KEY=... python3 server/forge.py`
- Coop relay (needed only for multiplayer): `python3 relay/relay.py`, then
  hub → Multijoueur. See `relay/README.md` to host it on a VPS.
- Tests: `GODOT=/path/to/godot tests/run.sh`

Controls: move WASD / arrows / left stick / left half of the screen; aim
with the mouse / right stick / right half. Main spell: left click (or aim
stick), secondary: right click / RB, ultimate: space / LB.

Game state: autoloads `Profile` (`game/profile.gd`: gold, shop, bonuses,
look, achievements, scores, spells; saved in `user://profile.json`) and
`Run` (`game/run.gd`: XP, level-ups, upgrades, waves). Base spells:
`game/spells.json`; level-up upgrades: `game/upgrades.gd`.

Design: `docs/design.md`. Spell format: `docs/spells.md`.
