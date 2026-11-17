import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

@Injectable()
export class PlayerService {
  constructor(private readonly prisma: PrismaService) {}

  async getProfile(uid: string): Promise<Prisma.JsonObject> {
    const player = await this.prisma.player.findUnique({ where: { uid } });
    return (player?.profile as Prisma.JsonObject | undefined) ?? {};
  }

  async putProfile(uid: string, profile: Prisma.JsonObject): Promise<void> {
    await this.prisma.player.upsert({
      where: { uid },
      create: { uid, profile },
      update: { profile },
    });
  }

  async getSpell(uid: string, id: string): Promise<Buffer | null> {
    const spell = await this.prisma.spell.findUnique({
      where: { uid_id: { uid, id } },
    });
    return spell ? Buffer.from(spell.bundle) : null;
  }

  async putSpell(uid: string, id: string, data: Buffer): Promise<void> {
    const bundle = new Uint8Array(data);
    await this.prisma.spell.upsert({
      where: { uid_id: { uid, id } },
      create: { uid, id, bundle },
      update: { bundle },
    });
  }
}
