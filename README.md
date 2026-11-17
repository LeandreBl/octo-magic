# octo-magic
Create, combine and cast spells to conquer a dungeon.

## Run

- Game: open the folder in Godot 4.7 (`godot --path .`).
- Spell forge (needed only to write on scrolls):
  `ANTHROPIC_API_KEY=... python3 server/forge.py`
- Coop relay (needed only for multiplayer): `python3 relay/relay.py`, then
  hub → Multijoueur. See `relay/README.md` to host it on a VPS.
- Online (web game, accounts, forge, coop relay): `cp example.env .env`, fill
  it, `docker compose up -d --build`, then http://localhost:8080 (relay on
  `ws://localhost:8770`). Server: `backend/server.js` (Firebase login,
  profiles and spells in Postgres).
- Tests: `GODOT=/path/to/godot tests/run.sh`

Controls: move WASD / arrows / left stick / left half of the screen; aim
with the mouse / right stick / right half. Spell: left click (or aim
stick); skill (shield, heal zone, mana zone: `game/skills.gd`): right click /
space / RB / LB.

Game state: autoloads `Profile` (`game/profile.gd`: gold, shop, bonuses,
look, achievements, scores, spells; saved in `user://profile.json`) and
`Run` (`game/run.gd`: XP, level-ups, upgrades, waves). Base spells:
`game/spells.json`; level-up upgrades: `game/upgrades.gd`.

Design: `docs/design.md`. Spell format: `docs/spells.md`.
