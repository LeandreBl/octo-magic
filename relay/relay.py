#!/usr/bin/env python3
"""Octo Magic coop relay: WebSocket rooms, no game logic.

One player hosts the game (peer id 1), the others join with a short code
(peer ids 2, 3, ...). The relay only forwards packets between them.

Protocol, over one WebSocket per player (text frames = JSON control,
binary frames = game packets):

  client -> relay  {"op": "host"}                  open a room
  relay -> host    {"op": "hosted", "code": "K7QX"}
  client -> relay  {"op": "join", "code": "K7QX"}
  relay -> client  {"op": "joined", "id": 2}
  relay -> host    {"op": "peer", "id": 2}         a player joined
  relay -> host    {"op": "left", "id": 2}         a player left
  host -> relay    {"op": "kick", "id": 2}
  relay -> any     {"op": "error", "msg": "..."}   then the socket closes

  binary: int32 little-endian peer id + payload. From the host the id is the
  target (0 = every client, N = client N, -N = every client but N); a client
  can only talk to the host. The relay rewrites the id to the sender's.

The room dies with its host: its clients are disconnected.

Run: python3 relay/relay.py [--port 8770]. Stdlib only (Python 3.8+).
"""
import argparse
import asyncio
import base64
import hashlib
import json
import logging
import secrets
import struct

MAX_MESSAGE = 1 << 16  # bytes, header included
MAX_BUFFERED = 1 << 20  # a reader this far behind is dropped
MAX_ROOMS = 1000
HELLO_TIMEOUT = 10.0
PING_EVERY = 20.0  # keeps proxies from closing quiet lobbies
CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I/L
CODE_LEN = 4
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TEXT, BINARY, CLOSE, PING, PONG = 1, 2, 8, 9, 10

log = logging.getLogger("relay")


class Closed(Exception):
    pass


# --- WebSocket framing (RFC 6455), shared with the tests' client -------------

def frame(opcode, data, mask=False):
    n = len(data)
    head = bytes([0x80 | opcode])
    bit = 0x80 if mask else 0
    if n < 126:
        head += bytes([bit | n])
    elif n < 1 << 16:
        head += bytes([bit | 126]) + struct.pack("!H", n)
    else:
        head += bytes([bit | 127]) + struct.pack("!Q", n)
    if mask:
        key = secrets.token_bytes(4)
        return head + key + xor(data, key)
    return head + data


def xor(data, key):
    n = len(data)
    k = int.from_bytes((key * (n // 4 + 1))[:n], "big")
    return (int.from_bytes(data, "big") ^ k).to_bytes(n, "big")


async def read_message(reader, masked=True, on_ping=None):
    """Next text/binary message -> (opcode, bytes). Control frames come back as
    is (CLOSE; PING and PONG too without on_ping, which else answers pings
    and skips pongs). Raises Closed on oversize or malformed frames."""
    op, parts, size = None, [], 0
    while True:
        b1, b2 = await reader.readexactly(2)
        opcode, n = b1 & 0x0F, b2 & 0x7F
        if n == 126:
            n = struct.unpack("!H", await reader.readexactly(2))[0]
        elif n == 127:
            n = struct.unpack("!Q", await reader.readexactly(8))[0]
        if bool(b2 & 0x80) != masked:
            raise Closed("bad masking")
        size += n
        if size > MAX_MESSAGE:
            raise Closed("message too big")
        key = await reader.readexactly(4) if masked else b""
        data = await reader.readexactly(n)
        if masked:
            data = xor(data, key)
        if opcode >= CLOSE:
            if opcode == CLOSE or not on_ping:
                return opcode, data
            if opcode == PING:
                on_ping(data)
            size -= n
            continue
        if opcode in (TEXT, BINARY):
            op, parts = opcode, []
        elif op is None:
            raise Closed("stray continuation")
        parts.append(data)
        if b1 & 0x80:
            return op, b"".join(parts)


class Conn:
    def __init__(self, reader, writer):
        self.reader, self.writer = reader, writer
        self.id = 0

    def send(self, opcode, data):
        if self.writer.is_closing():
            return
        if self.writer.transport.get_write_buffer_size() > MAX_BUFFERED:
            log.info("dropping a slow reader")
            self.writer.close()
            return
        self.writer.write(frame(opcode, data))

    def send_json(self, **msg):
        self.send(TEXT, json.dumps(msg).encode())

    def close(self, reason=""):
        if reason:
            self.send_json(op="error", msg=reason)
        self.send(CLOSE, struct.pack("!H", 1000))
        self.writer.close()

    async def recv(self):
        op, data = await read_message(self.reader, on_ping=lambda d: self.send(PONG, d))
        if op == CLOSE:
            raise Closed()
        return op, data


async def handshake(reader, writer):
    try:
        request = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), HELLO_TIMEOUT)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError):
        return False
    headers = {}
    for line in request.decode("latin-1").split("\r\n")[1:]:
        k, _, v = line.partition(":")
        headers[k.strip().lower()] = v.strip()
    key = headers.get("sec-websocket-key")
    if not key or headers.get("upgrade", "").lower() != "websocket":
        writer.write(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
        return False
    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                  "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept).encode())
    return True


# --- rooms -------------------------------------------------------------------

class Room:
    def __init__(self, code, host):
        self.code, self.host = code, host
        self.clients = {}  # id -> Conn
        self.next_id = 2


class Relay:
    def __init__(self, max_players=4):
        self.max_players = max_players
        self.rooms = {}

    def new_code(self):
        while True:
            code = "".join(secrets.choice(CODE_CHARS) for _ in range(CODE_LEN))
            if code not in self.rooms:
                return code

    async def handle(self, reader, writer):
        conn = Conn(reader, writer)
        pinger = None
        try:
            if not await handshake(reader, writer):
                return
            pinger = asyncio.ensure_future(self.ping(conn))
            op, data = await asyncio.wait_for(conn.recv(), HELLO_TIMEOUT)
            hello = json.loads(data) if op == TEXT else {}
            if not isinstance(hello, dict):
                hello = {}
            if hello.get("op") == "host":
                await self.run_host(conn)
            elif hello.get("op") == "join":
                await self.run_client(conn, str(hello.get("code", "")).strip().upper())
            else:
                conn.close("bad hello")
        except (Closed, OSError, asyncio.IncompleteReadError, asyncio.TimeoutError, ValueError) as e:
            if isinstance(e, Closed) and str(e):
                conn.close(str(e))
        finally:
            if pinger:
                pinger.cancel()
            writer.close()

    async def ping(self, conn):
        while True:
            await asyncio.sleep(PING_EVERY)
            conn.send(PING, b"")

    async def run_host(self, conn):
        if len(self.rooms) >= MAX_ROOMS:
            return conn.close("relay full")
        room = Room(self.new_code(), conn)
        conn.id = 1
        self.rooms[room.code] = room
        log.info("room %s opened (%d rooms)", room.code, len(self.rooms))
        conn.send_json(op="hosted", code=room.code)
        try:
            while True:
                op, data = await conn.recv()
                if op == BINARY and len(data) >= 4:
                    target = struct.unpack_from("<i", data)[0]
                    out = struct.pack("<i", 1) + data[4:]
                    for cid, c in list(room.clients.items()):
                        if target == 0 or target == cid or (target < 0 and cid != -target):
                            c.send(BINARY, out)
                elif op == TEXT:
                    msg = json.loads(data)
                    if isinstance(msg, dict) and msg.get("op") == "kick" and isinstance(msg.get("id"), int):
                        kicked = room.clients.get(msg["id"])
                        if kicked:
                            kicked.close("kicked")
        finally:
            del self.rooms[room.code]
            for c in room.clients.values():
                c.close("host left")
            log.info("room %s closed", room.code)

    async def run_client(self, conn, code):
        room = self.rooms.get(code)
        if not room:
            return conn.close("no such room")
        if len(room.clients) + 1 >= self.max_players:
            return conn.close("room full")
        conn.id = room.next_id
        room.next_id += 1
        room.clients[conn.id] = conn
        conn.send_json(op="joined", id=conn.id)
        room.host.send_json(op="peer", id=conn.id)
        try:
            while True:
                op, data = await conn.recv()
                if op == BINARY and len(data) >= 4:
                    room.host.send(BINARY, struct.pack("<i", conn.id) + data[4:])
        finally:
            if room.clients.pop(conn.id, None):
                room.host.send_json(op="left", id=conn.id)


async def serve(host, port, max_players):
    relay = Relay(max_players)
    server = await asyncio.start_server(relay.handle, host, port, limit=8192)
    return relay, server


def main():
    p = argparse.ArgumentParser(description="Octo Magic coop relay")
    p.add_argument("--host", default="0.0.0.0", help="bind address")
    p.add_argument("--port", type=int, default=8770)
    p.add_argument("--max-players", type=int, default=4, help="per room, host included")
    a = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

    async def run():
        _, server = await serve(a.host, a.port, a.max_players)
        log.info("relay on ws://%s:%d", a.host, a.port)
        async with server:
            await server.serve_forever()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
