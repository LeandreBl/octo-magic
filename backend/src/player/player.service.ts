import { Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

export const MAX_CHARACTERS = 10;
const CHARACTER = { id: true, name: true, spell: true, updatedAt: true } as const;

@Injectable()
export class PlayerService {
  constructor(private readonly prisma: PrismaService) {}

  listCharacters(uid: string) {
    return this.prisma.character.findMany({
      where: { uid },
      select: CHARACTER,
      orderBy: { createdAt: "asc" },
    });
  }

  // ponytail: count then create is racy, two parallel creations may pass MAX_CHARACTERS by one.
  async createCharacter(uid: string, name: string, spell: string, profile: Prisma.JsonObject) {
    if ((await this.prisma.character.count({ where: { uid } })) >= MAX_CHARACTERS) {
      return null;
    }
    return this.prisma.character.create({ data: { uid, name, spell, profile }, select: CHARACTER });
  }

  async deleteCharacter(uid: string, id: string): Promise<void> {
    const { count } = await this.prisma.character.deleteMany({ where: { uid, id } });
    if (!count) throw new NotFoundException("no such character");
  }

  async getProfile(uid: string, id: string): Promise<Prisma.JsonObject> {
    const c = await this.prisma.character.findFirst({ where: { uid, id } });
    if (!c) throw new NotFoundException("no such character");
    return c.profile as Prisma.JsonObject;
  }

  async putProfile(uid: string, id: string, profile: Prisma.JsonObject): Promise<void> {
    const { count } = await this.prisma.character.updateMany({ where: { uid, id }, data: { profile } });
    if (!count) throw new NotFoundException("no such character");
  }

  async deleteAll(uid: string): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.character.deleteMany({ where: { uid } }),
      this.prisma.spell.deleteMany({ where: { uid } }),
    ]);
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
