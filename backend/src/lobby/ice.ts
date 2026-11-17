import { createHmac } from "node:crypto";

const TURN_TTL = 12 * 3600; // seconds

export type Turn = { url?: string; secret?: string };

export type IceServer = { urls: string[]; username?: string; credential?: string };

/** RTCIceServer list for one player: public STUN, and TURN with time-limited
 * credentials (coturn's TURN REST API scheme, --use-auth-secret). */
export function iceServers(uid: string, turn?: Turn, now = Date.now() / 1000): IceServer[] {
  const ice: IceServer[] = [{ urls: ["stun:stun.l.google.com:19302"] }];
  if (turn?.url && turn.secret) {
    const username = `${Math.floor(now) + TURN_TTL}:${uid}`;
    ice.push({
      urls: [turn.url],
      username,
      credential: createHmac("sha1", turn.secret).update(username).digest("base64"),
    });
  }
  return ice;
}
