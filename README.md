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
- Account in the game: hub → Compte (email/password, Firebase). Logged in,
  the profile and forged spells follow the account and the forge works. The
  native game talks to `http://localhost:8080` (`OCTO_SERVER` or
  `octo/server_url` in `project.godot` to change it); see `game/online.gd`.
- Tests: `GODOT=/path/to/godot tests/run.sh`

Controls: move WASD / arrows / left stick / left half of the screen; aim
with the mouse / right stick / right half. Main spell: left click (or aim
stick), secondary: right click / RB, ultimate: space / LB. Pause: Escape /
Start. Keys can be rebound in Options.

Game state: autoloads `Profile` (`game/profile.gd`: gold, shop, bonuses,
look, achievements, scores, spells; saved in `user://profile.json`) and
`Run` (`game/run.gd`: XP, level-ups, upgrades, waves). Base spells:
`game/spells.json`; level-up upgrades: `game/upgrades.gd`.

Screens (menus, HUD, level-up, shop, options, theme) are in `ui/`, entry
`ui/ui.gd`; options are saved in `user://settings.cfg`.

Design: `docs/design.md`. Spell format: `docs/spells.md`.
