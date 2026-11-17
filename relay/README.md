# Coop relay

Forwards packets between the host of a coop game and its players. No game
logic: the host runs the game (`game/main.gd`), the relay only routes. Stdlib
Python, protocol in the docstring of `relay.py`.

    python3 relay/relay.py              # ws://0.0.0.0:8770
    python3 relay/relay.py --port 9000 --max-players 4

The game connects to `ws://localhost:8770` by default; the lobby has a field
for another address (or set `OCTO_RELAY`). Tests: `tests/run.sh` (the relay,
plus two headless games through it when Godot is found).

## On a VPS

Run it bound to localhost and let the web server add TLS (a game served over
https must use `wss://`). As a service: `python3 /opt/octo-magic/relay/relay.py
--host 127.0.0.1` in a systemd unit with `Restart=always`.

Caddy (certificate included):

    relay.example.com {
        reverse_proxy 127.0.0.1:8770
    }

nginx:

    location / {
        proxy_pass http://127.0.0.1:8770;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 120s;  # the relay pings every 20 s
    }

Then the lobby address is `wss://relay.example.com`.

Limits: 64 KiB per message, 4 players per room (host included), 1000 rooms,
a reader more than 1 MiB behind is dropped. No per-IP limit yet: add one (or
a firewall rule) if the relay gets abused.
