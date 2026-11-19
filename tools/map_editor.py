"""Edit a map's zones in the browser: its solid polygons and circles, the open
graves monsters come out of, the mages' start and the lamps lit in the night (assets/maps/<name>/map.json,
over its ground.png and above.png), with a test character walking as in the
game.

    python3 tools/map_editor.py graveyard [port]    # then open http://localhost:8765

Save writes map.json (the previous one kept as map.json.bak).
"""

import json
import re
import shutil
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PORT = 8765


def main():
    folder = ROOT / "assets/maps" / (sys.argv[1] if len(sys.argv) > 1 else "graveyard")
    port = int(sys.argv[2]) if len(sys.argv) > 2 else PORT
    page = Path(__file__).parent / "map_editor.html"  # read on each load: an edit shows on reload

    class Handler(BaseHTTPRequestHandler):
        def _send(self, body: bytes, kind: str, code: int = 200):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            arena = (ROOT / "game/arena.gd").read_text()
            config = {k: float(re.search(rf"const {k.upper()} := ([\d.]+)", arena).group(1)) for k in ("scale", "see", "faded", "body", "lamp_light")}
            files = {"/": (page.read_bytes(), "text/html; charset=utf-8"),
                     "/config": (json.dumps(config).encode(), "application/json"),
                     "/octo.png": ((ROOT / "assets/octo/idle.png").read_bytes(), "image/png"),
                     "/ground.png": ((folder / "ground.png").read_bytes(), "image/png"),
                     "/map.json": ((folder / "map.json").read_bytes(), "application/json")}
            files["/above.png"] = ((folder / "above.png").read_bytes(), "image/png")
            if self.path in files:
                self._send(*files[self.path])
            else:
                self._send(b"not found", "text/plain", 404)

        def do_POST(self):
            if self.path != "/save":
                return self._send(b"not found", "text/plain", 404)
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            for key in ("polygons", "circles", "spawns", "start", "lamps"):  # what the game reads (game/arena.gd)
                if key not in data:
                    return self._send(f"missing {key}".encode(), "text/plain", 400)
            shutil.copy(folder / "map.json", folder / "map.json.bak")
            (folder / "map.json").write_text(dump(data))
            self._send(b"saved", "text/plain")

        def log_message(self, *args):
            pass

    print(f"editing {folder}/map.json: http://localhost:{port}")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


def dump(data: dict) -> str:
    """map.json with one zone per line (readable diffs)."""
    lines = []
    for k, v in data.items():
        if isinstance(v, list) and v and isinstance(v[0], list):
            lines.append(f" {json.dumps(k)}: [\n" + ",\n".join("  " + json.dumps(e) for e in v) + "\n ]")
        else:
            lines.append(f" {json.dumps(k)}: {json.dumps(v)}")
    return "{\n" + ",\n".join(lines) + "\n}\n"


if __name__ == "__main__":
    main()
