# octo-magic
Create, combine and cast spells to conquer a graveyard. A top-down twin-stick
roguelite: you are an octopus mage, waves of undead come out of the tombs,
and the spells are words you write on scrolls, forged by an AI.

## What the game does

### A run
- One map: a hand-painted graveyard (`game/arena.gd`, zones in
  `assets/maps/graveyard/map.json`, edited with `tools/map_editor.py`). Trees and
  roofs are drawn above the mage and fade around it when it walks under them;
  mages and monsters slide around walls, tombs and trees.
- Endless waves of growing size and strength. Monsters come out of open tombs,
  never inside a player's view; a boss every 5 waves.
- XP from kills: each level gives full health and mana back and blasts the
  monsters around the mage away.
- Drops: gold, mana and life orbs, blank scrolls, red and blue grimoires, and
  Quad Damage (x4 damage for 10 s). Everything on the floor flies to the mage
  at the end of a wave.
- Grimoires: a choice of 3 skills (red: hero, blue: spell); each pick raises a
  skill one level (I, II, III...) up to its max. Skills (`game/upgrades.gd`):
  Robur (HP), Receptaculum (mana), Fluxus (mana regen), Celeritas (cast rate),
  Pernicitas (speed), Magnes (pickup radius), Antidotum and Tutela Ignis
  (poison and fire resistance), Inspiratio (a 4th card), Parsimonia (mana cost),
  Potentia (damage), Meditatio (x4 mana regen standing still).
  Sub-skills augment one base spell and are offered only when it is the run's
  spell; engine stats, never spell data, so no scroll can forge them: Catena
  (Fulmen's arc jumps on to +1 enemy a level, up to V), Procella (Flatus
  Gelidus pushes the enemies it strikes back, harder each level, up to V), Aether
  (-12 % Fulmen mana cost a level, up to V), Ventus Algidus (Flatus Gelidus
  slows its targets by 10 % a level, up to V), Rigor
  (Flatus Gelidus freezes its targets for 0.6 s, +3 % chance a strike a level,
  up to V), Plura Tela (Telum Magicum fires +1 missile a level, up to V), Conus Glaciei
  (Flatus Gelidus's cone +15 % longer and wider a level, up to V), Favillae
  (Pila Ignea leaves a trail of burning embers, +2 damage a tick a level, up to V), Immolatio (Pila Ignea sets its
  targets on fire, +5 burn a second a level, up to V).
- Permadeath: the run ends when every mage is down; gold and scrolls are kept.
  A solo run is saved at the start of each wave (pause → Save and quit), in
  the cloud with the character: Play continues it on any device.
- Score from kills, waves and bosses; local leaderboard (best 10).

### Monsters (`Run.ENEMIES`, `game/enemy.gd`)
- Undead only: skeletons, imps, archers and marksmen, zombies, skeletal
  warriors (helmet) and knights (gauntlets), wraiths, poison, frost, fire and
  lightning mages (some shielded), rotting zombies (leave poison pools),
  burning skeletons and archers, putrid archers.
- AIs: chase, weave (zigzags), still (archers and mages hold still once on
  screen). They attack only from on screen; ground attacks are always
  telegraphed.
- Effects on the mage: poison, freeze (slowed), stun, and fire damage.
- Bosses (`Run.BOSSES`): Lich King (wave 5: shot rings, summons skeletons),
  then the boss monsters, each adding an attack to the last one's: Bone Herald
  (10, missile volleys), Pyre Lord (15, + fire pools), Blight Eye (20, + green
  laser), Grave Maw (25, + vanishes and bites), Archfiend (30 and every 5th
  wave after, + fire pools hatching hell imps, more each time). A boss dies in
  a staggering explosion (`game/boss_death.gd`) and scatters gold.

### The mage
- An octopus seen from above (PixelLab sprites), with 8 physics tentacles that
  crawl, swim behind it at full speed and bump into walls and monsters
  (`game/tentacle.gd`, visual only).
- Stats as data (`game/stats.gd`): HP, HP and mana regen, mana, mana cost,
  cooldown, cast rate, speed, pickup radius, armor, crit (x2 per cast),
  damage, gold, XP, poison and fire resistance, orbs, luck, grimoire choices.
  Every source (equipment, bonuses, perks, skills) is a bonus on them.
- One spell (left click), plus an active augment as secondary spell (right
  click / Space / RB). Short of mana, a spell still casts,
  weakened to the share of mana left.

### Spells (`spell/`, format in `docs/spells.md`)
- A spell is data: bodies (bolt, zone, beam, cone), patterns, motions (homing,
  wave, accelerate, boomerang, orbit), effects (damage, burn, poison, slow,
  freeze, stun, knockback, heal, sub-casts up to 3 deep). The engine clamps
  everything and prices it in mana: the AI describes, the engine balances.
- Sounds synthesized from the spell data (`spell/spell_sound.gd`), pixel art
  from its grids or its PixelLab sheets.
- 8 base spells (`game/spells.json`): 4 to start a character with, 4 unlocked
  by achievements.

### The forge (between runs, logged in)
- One word per blank scroll, in a dead language (Latin, Ancient Greek, Old
  Norse, Sanskrit...); several scrolls at once. A meaningless or living-language
  word is cancelled and its scroll given back.
- The server's forge (Claude, `server/forge.py`) rewrites the spell with the
  words and PixelLab draws its projectile, impact and icon; the result is a
  `.spell` bundle tied to the account. Several forges can run in parallel
  while you play; the new spell is equipped at the next run.

### Between runs
- Shop (`ui/shop.gd`): staffs, robes and rings; permanent bonuses (Vitality,
  Power, Focus, Swiftness, Frugality, Endurance, Keen eye, Attraction, Greed,
  Wisdom, and Feeling perky: +1 augment slot, twice); augments, bought once,
  3 slots per run: Ring of fire (active), Shield, and perks (Life up, Mana up,
  Quick feet, Creativity, Poison ward, Telekinesis, Battle mage, Scavenger,
  Blaze of glory, Fast caster, Potions, Gold rush, Head start, Great start,
  Weird eye, Lucky drops, Hardcore); the mage's look.
- Records (menu → Palmarès): 13 achievements, some unlocking spells; leaderboard;
  stats.

### Online
- Account (email/password or Google, Firebase), several characters per
  account (renamed or deleted on the characters screen), each with its
  profile, spells and saved run, synced to the server.
- Coop up to 8 players, WebRTC peer to peer (`game/net.gd`, `game/lobby.gd`):
  the host runs the game, each player keeps its own run; kills and drops are
  shared; players can join mid-run.
- Website (`web/`): landing page, account with stats and deletion, the web
  game, terms and privacy, in French and English.

### Everywhere
- Keyboard and mouse, gamepad, or touch (left half moves, right half aims).
- Options: language (English, French), UI size, fullscreen, volumes, key
  rebinding.
- 14 music tracks (`assets/music/CREDITS.md`), retro sound effects synthesized
  at startup (`game/sfx.gd`).

## Code map
- `game/`: the game scene `main.gd` (waves, drops, coop wiring) and autoloads
  `Run` (`run.gd`: the current run, monster and boss data, waves), `Profile`
  (`profile.gd`: everything kept between runs, shop data, achievements, saved
  in `user://profile.json`), `Online` (`online.gd`: account and server),
  `Sfx`. Data-only classes: `Stats`, `Upgrades` (grimoire skills).
- `spell/`: the spell engine (`Spell`: sanitize, price, damage scaling;
  `SpellBody`, `SpellArt`, `SpellSound`).
- `ui/`: every screen (entry `ui/ui.gd`), HUD, shop, forge, options
  (`user://settings.cfg`), theme.
- `server/`: the spell forge (Python). `backend/`: the NestJS server. `web/`:
  the website. `tools/`: PixelLab art generators and the map editor.
- Design decisions: `docs/design.md`.

## Run

- Game: open the folder in Godot 4.7 (`godot --path .`).
- Spell forge (needed only to write on scrolls):
  `ANTHROPIC_API_KEY=... python3 server/forge.py`
- Online (website, web game, accounts, forge, coop lobby, TURN):
  `cp example.env .env`, fill it, `docker compose up -d --build`, then
  http://localhost:8080.
  Locally without `ANTHROPIC_API_KEY` nor `CLAUDE_CODE_OAUTH_TOKEN`, also run
  `python3 server/forge.py` (your logged-in `claude` CLI) and set
  `FORGE_URL=http://host.docker.internal:8765` in `.env`. On the
  VPS, behind Traefik: https://octo-magic.notdotio.com (website and game),
  https://octo-magic.api.notdotio.com (API), TURN on
  octo-magic.turn.notdotio.com (see the end of `example.env`).
  Website: static pages without a build, same Firebase login as the game,
  shared with the web game through localStorage (`web/site.js`). `./web.sh`
  exports the game into `web/godot` for local dev.
  Server: NestJS in TypeScript (Firebase login guard, profiles and spells in
  Postgres through Prisma, forge proxy, coop lobby on `/play`, serves `web/`);
  API docs on `/api/docs`. Local dev: `cd backend && npm i && npm run start:dev`
  (with the variables of `example.env` and a `DATABASE_URL`); migrations in
  `backend/prisma/migrations`, applied at container start-up.
- Coop (menu → Coop, logged in): the server only introduces the
  players. The native game needs the WebRTC extension: `./webrtc.sh`
  (downloads `addons/webrtc_native`, not in git).
- Account in the game: menu → the character's name (top right) → Compte. Google needs, in the Firebase/Google
  Cloud console: the Google provider on, authorized domain
  `octo-magic.notdotio.com`, and on its OAuth web client the redirect URIs
  `https://octo-magic.notdotio.com/account` (site and web game) and
  `http://localhost:47815/` (native game). The native game talks to
  https://octo-magic.api.notdotio.com (`OCTO_SERVER=http://localhost:8080` for
  a local server); see `game/online.gd`.
- Tests: `GODOT=/path/to/godot tests/run.sh`. Screenshots by hand:
  `tests/shot.gd`, `tests/shot_forge.gd`.
