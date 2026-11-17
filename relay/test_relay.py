import asyncio
import base64
import json
import os
import shutil
import struct
import subprocess
import sys
import unittest

import relay

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Client:
    opened = []

    @classmethod
    async def open(cls, port):
        c = cls()
        cls.opened.append(c)
        c.reader, c.writer = await asyncio.open_connection("127.0.0.1", port)
        key = base64.b64encode(os.urandom(16)).decode()
        c.writer.write(("GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
        assert b" 101 " in await c.reader.readuntil(b"\r\n\r\n")
        return c

    def send(self, msg):
        self.writer.write(relay.frame(relay.TEXT, json.dumps(msg).encode(), mask=True))

    def packet(self, peer, payload):
        self.writer.write(relay.frame(relay.BINARY, struct.pack("<i", peer) + payload, mask=True))

    async def recv(self):
        while True:
            op, data = await asyncio.wait_for(relay.read_message(self.reader, masked=False), 2)
            if op == relay.TEXT:
                return json.loads(data)
            if op == relay.BINARY:
                return struct.unpack_from("<i", data)[0], data[4:]
            if op == relay.CLOSE:
                return "closed"


class RelayTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.relay, self.server = await relay.serve("127.0.0.1", 0, max_players=3)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        for c in Client.opened:
            c.writer.close()
        Client.opened.clear()
        self.server.close()
        await self.server.wait_closed()

    async def room(self, clients=1):
        host = await Client.open(self.port)
        host.send({"op": "host"})
        msg = await host.recv()
        self.assertEqual(msg["op"], "hosted")
        out = []
        for i in range(clients):
            c = await Client.open(self.port)
            c.send({"op": "join", "code": msg["code"].lower()})
            self.assertEqual(await c.recv(), {"op": "joined", "id": 2 + i})
            self.assertEqual(await host.recv(), {"op": "peer", "id": 2 + i})
            out.append(c)
        return msg["code"], host, out

    async def test_packets_routed_with_sender_id(self):
        _, host, (a, b) = await self.room(2)
        a.packet(99, b"hi")  # clients always reach the host
        self.assertEqual(await host.recv(), (2, b"hi"))
        host.packet(0, b"all")
        self.assertEqual(await a.recv(), (1, b"all"))
        self.assertEqual(await b.recv(), (1, b"all"))
        host.packet(3, b"b")
        self.assertEqual(await b.recv(), (1, b"b"))
        host.packet(-3, b"not b")
        self.assertEqual(await a.recv(), (1, b"not b"))
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(b.recv(), 0.2)

    async def test_bad_code_and_full_room(self):
        code, _, _ = await self.room(2)
        for c in ["NOPE", code]:
            cl = await Client.open(self.port)
            cl.send({"op": "join", "code": c})
            self.assertEqual((await cl.recv())["op"], "error")

    async def test_host_leaving_closes_room(self):
        code, host, (a,) = await self.room(1)
        host.writer.close()
        self.assertEqual(await a.recv(), {"op": "error", "msg": "host left"})
        await asyncio.sleep(0.05)
        self.assertNotIn(code, self.relay.rooms)

    async def test_client_leaving_and_kick(self):
        _, host, (a, b) = await self.room(2)
        a.writer.close()
        self.assertEqual(await host.recv(), {"op": "left", "id": 2})
        host.send({"op": "kick", "id": 3})
        self.assertEqual(await b.recv(), {"op": "error", "msg": "kicked"})
        self.assertEqual(await host.recv(), {"op": "left", "id": 3})

    async def test_oversize_message_closes(self):
        _, host, (a,) = await self.room(1)
        a.packet(1, b"x" * relay.MAX_MESSAGE)
        self.assertEqual(await a.recv(), {"op": "error", "msg": "message too big"})
        self.assertEqual(await host.recv(), {"op": "left", "id": 2})

    async def test_fragmented_message_reassembled(self):
        _, host, (a,) = await self.room(1)
        first = bytearray(relay.frame(relay.BINARY, struct.pack("<i", 1) + b"ab", mask=True))
        first[0] &= 0x7F  # FIN off
        a.writer.write(bytes(first) + relay.frame(relay.PING, b"", mask=True) + relay.frame(0, b"cd", mask=True))
        self.assertEqual(await host.recv(), (2, b"abcd"))


@unittest.skipUnless(shutil.which(os.environ.get("GODOT", "godot")), "godot not found")
class GodotEndToEnd(unittest.TestCase):
    """Two headless games through the relay: one hosts, one joins."""

    cmd = [shutil.which(os.environ.get("GODOT", "godot")) or "godot", "--headless", "--path", ROOT,
           "--script", "tests/net_e2e.gd", "--"]

    def test_solo_is_a_host_alone(self):
        out = subprocess.run(self.cmd + ["solo"], capture_output=True, text=True, timeout=60)
        self.assertIn("E2E OK", out.stdout, out.stdout + out.stderr)
        self.assertNotIn("ERROR", out.stdout + out.stderr)

    def test_two_headless_games(self):
        server = subprocess.Popen([sys.executable, os.path.join(ROOT, "relay", "relay.py"),
                                   "--host", "127.0.0.1", "--port", "18770"], stderr=subprocess.DEVNULL)
        procs = [server]
        try:
            cmd = self.cmd
            host = subprocess.Popen(cmd + ["host", "ws://127.0.0.1:18770"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            procs.append(host)
            code = ""
            for line in host.stdout:
                if line.startswith("CODE "):
                    code = line.split()[1]
                    break
            self.assertTrue(code, "host got no room code")
            client = subprocess.run(cmd + ["join", "ws://127.0.0.1:18770", code],
                                    capture_output=True, text=True, timeout=60)
            self.assertIn("E2E OK", client.stdout, client.stdout + client.stderr)
            self.assertNotIn("ERROR", client.stdout + client.stderr)
            out, _ = host.communicate(timeout=30)
            self.assertIn("E2E OK", out, out)
            self.assertNotIn("ERROR", out)
        finally:
            for p in procs:
                if p.poll() is None:
                    p.kill()
                    p.wait()


if __name__ == "__main__":
    unittest.main()
