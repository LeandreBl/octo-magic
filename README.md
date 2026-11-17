# octo-magic
Create, combine and cast spells to conquer a dungeon.

## Run

- Game: open the folder in Godot 4.7 (`godot --path .`).
- Spell forge (needed only to write on scrolls):
  `ANTHROPIC_API_KEY=... python3 server/forge.py`
- Online (web game, accounts, forge, coop lobby, TURN): `cp example.env .env`,
  fill it, `docker compose up -d --build`, then http://localhost:8080.
  Locally without `ANTHROPIC_API_KEY`, also run `python3 server/forge.py`:
  the forge then uses your logged-in `claude` CLI (Claude account). On the
  VPS, behind Traefik: https://octo-magic.notdotio.com (game),
  https://octo-magic.api.notdotio.com (API), TURN on
  octo-magic.turn.notdotio.com (see the end of `example.env`).
  Server: `backend/`, NestJS in TypeScript (Firebase login guard,
  profiles and spells in Postgres through Prisma, forge proxy, coop lobby
  on `/play`, `/terms` and `/privacy` from `backend/legal/`); API docs
  on `/api/docs`. Local dev: `cd backend && npm i &&
  npm run start:dev` (with the variables of `example.env` and a
  `DATABASE_URL`); migrations in `backend/prisma/migrations`, applied at
  container start-up.
- Coop (menu → Multijoueur, logged in): WebRTC peer to peer, the server only
  introduces the players (`game/net.gd`). The native game needs the WebRTC
  extension: `./webrtc.sh` (downloads `addons/webrtc_native`, not in git).
- Account in the game: menu → Compte (email/password, Firebase). Logged in,
  the profile and forged spells follow the account and the forge works. The
  native game talks to https://octo-magic.api.notdotio.com
  (`OCTO_SERVER=http://localhost:8080` for a local server); see
  `game/online.gd`.
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
