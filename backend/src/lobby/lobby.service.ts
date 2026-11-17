import { randomInt } from "node:crypto";
import type { Server } from "node:http";
import { Injectable, OnApplicationBootstrap, OnApplicationShutdown } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { HttpAdapterHost } from "@nestjs/core";
import { WebSocket, WebSocketServer } from "ws";
import { FirebaseService } from "../auth/firebase.service";
import { iceServers, Turn } from "./ice";

const MAX_SIGNAL = 64 * 1024;
const MAX_PLAYERS = 8;
const MAX_ROOMS = 1000;
const HELLO_TIMEOUT = 10_000;
const PING_EVERY = 20_000; // keeps proxies from closing quiet lobbies
const CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I/L

/** Peer id -> socket. The host is 1, players 2, 3... */
type Room = Map<number, WebSocket>;

type Message = { op?: unknown; token?: unknown; code?: unknown; to?: unknown; data?: unknown };

/**
 * The coop lobby, WebSocket /play: rooms with a short code, WebRTC signaling.
 * Games run peer to peer; the lobby only introduces the players, the TURN
 * server relays when they cannot reach each other. JSON text messages:
 *
 *   -> {"op": "host", "token": T}           open a room
 *   <- {"op": "hosted", "code": "K7QX", "id": 1, "ice": [RTCIceServer...]}
 *   -> {"op": "join", "code": "K7QX", "token": T}
 *   <- {"op": "joined", "id": 2, "ice": [...]}
 *   <- {"op": "peer", "id": 2}              to the host: a player joined
 *   <- {"op": "left", "id": 2}              to the host: a player left
 *   -> {"op": "signal", "to": 1, "data": D} WebRTC offer/answer/candidate
 *   <- {"op": "signal", "from": 2, "data": D}
 *   <- {"op": "error", "msg": "..."}        then the socket closes
 *
 * A player talks to the host only (the host's game relays between players).
 * The room dies with its host.
 */
@Injectable()
export class LobbyService implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly rooms = new Map<string, Room>();
  private readonly turn: Turn;
  private wss?: WebSocketServer;
  private pinger?: NodeJS.Timeout;

  constructor(
    private readonly adapterHost: HttpAdapterHost,
    private readonly firebase: FirebaseService,
    config: ConfigService,
  ) {
    this.turn = { url: config.get("TURN_URL"), secret: config.get("TURN_SECRET") };
  }

  onApplicationBootstrap() {
    const server: Server | undefined = this.adapterHost.httpAdapter?.getHttpServer();
    if (!server) return; // an application context without HTTP (scripts)
    this.wss = new WebSocketServer({ server, path: "/play", maxPayload: MAX_SIGNAL });
    this.wss.on("connection", (ws) => this.connect(ws));
    this.pinger = setInterval(() => this.wss?.clients.forEach((ws) => ws.ping()), PING_EVERY);
    this.pinger.unref();
  }

  onApplicationShutdown() {
    clearInterval(this.pinger);
    this.wss?.clients.forEach((ws) => ws.terminate());
    this.wss?.close();
  }

  private send(ws: WebSocket | undefined, msg: object) {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(msg));
    }
  }

  private fail(ws: WebSocket, msg: string) {
    this.send(ws, { op: "error", msg });
    ws.close();
  }

  private connect(ws: WebSocket) {
    let room: Room | null = null;
    let id = 0;
    let greeted = false;
    const hello = setTimeout(() => this.fail(ws, "no hello"), HELLO_TIMEOUT);
    ws.on("error", () => {});
    ws.on("close", () => clearTimeout(hello));
    ws.on("message", async (raw, binary) => {
      let msg: Message | null;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        msg = null;
      }
      if (binary || !msg || typeof msg !== "object") {
        return this.fail(ws, "bad message");
      }
      if (msg.op === "signal" && room) {
        const to = room.get(msg.to as number);
        // A player reaches the host only; the host reaches its players.
        if (to && to !== ws && (id === 1 || msg.to === 1)) {
          this.send(to, { op: "signal", from: id, data: msg.data });
        }
        return;
      }
      if (greeted || (msg.op !== "host" && msg.op !== "join")) {
        return this.fail(ws, "bad message");
      }
      greeted = true;
      clearTimeout(hello);
      let uid: string;
      try {
        ({ uid } = await this.firebase.verifyToken(String(msg.token ?? "")));
      } catch {
        return this.fail(ws, "invalid token");
      }
      if (ws.readyState !== WebSocket.OPEN) {
        return;
      }
      if (msg.op === "host") {
        if (this.rooms.size >= MAX_ROOMS) {
          return this.fail(ws, "server full");
        }
        let code: string;
        do {
          code = Array.from({ length: 4 }, () => CODE_CHARS[randomInt(CODE_CHARS.length)]).join("");
        } while (this.rooms.has(code));
        const hosted: Room = new Map([[1, ws]]);
        this.rooms.set(code, hosted);
        room = hosted;
        id = 1;
        ws.on("close", () => {
          this.rooms.delete(code);
          for (const [pid, p] of hosted) {
            if (pid !== 1) this.fail(p, "host left");
          }
        });
        return this.send(ws, { op: "hosted", code, id, ice: iceServers(uid, this.turn) });
      }
      const joined = this.rooms.get(String(msg.code ?? "").toUpperCase());
      if (!joined) {
        return this.fail(ws, "no such room");
      }
      if (joined.size >= MAX_PLAYERS) {
        return this.fail(ws, "room full");
      }
      room = joined;
      id = 2;
      while (joined.has(id)) id++;
      const me = id;
      joined.set(me, ws);
      ws.on("close", () => {
        if (joined.get(me) !== ws) return;
        joined.delete(me);
        this.send(joined.get(1), { op: "left", id: me });
      });
      this.send(ws, { op: "joined", id: me, ice: iceServers(uid, this.turn) });
      this.send(joined.get(1), { op: "peer", id: me });
    });
  }
}
