import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Param,
  Post,
  Put,
  StreamableFile,
  UseGuards,
} from "@nestjs/common";
import {
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiOperation,
  ApiProduces,
  ApiTags,
} from "@nestjs/swagger";
import { Prisma } from "@prisma/client";
import { AuthUser, CurrentUser } from "../auth/current-user.decorator";
import { FirebaseAuthGuard } from "../auth/firebase-auth.guard";
import { PlayerService } from "./player.service";

const SPELL_ID = /^[\w-]{1,64}$/;

function spellId(id: unknown): string {
  if (typeof id !== "string" || !SPELL_ID.test(id)) {
    throw new BadRequestException("invalid spell id");
  }
  return id;
}

function jsonObject(v: unknown, what: string): Prisma.JsonObject {
  if (!v || typeof v !== "object" || Array.isArray(v)) {
    throw new BadRequestException(`${what} must be an object`);
  }
  return v as Prisma.JsonObject;
}

@ApiTags("player")
@ApiBearerAuth()
@UseGuards(FirebaseAuthGuard)
@Controller()
export class PlayerController {
  constructor(private readonly players: PlayerService) {}

  @Get("characters")
  @ApiOperation({ summary: "The account's characters [{id, name, spell, updatedAt}], oldest first" })
  listCharacters(@CurrentUser() user: AuthUser) {
    return this.players.listCharacters(user.uid);
  }

  @Post("characters")
  @ApiOperation({ summary: "A new character: {name, spell (starting spell id), profile? ({} by default)}" })
  @ApiBody({ schema: { type: "object" } })
  async createCharacter(@CurrentUser() user: AuthUser, @Body() body: unknown) {
    const { name, spell, profile = {} } = jsonObject(body, "body");
    const trimmed = typeof name === "string" ? name.trim() : "";
    if (!trimmed || trimmed.length > 24) {
      throw new BadRequestException("name must be 1 to 24 characters");
    }
    const c = await this.players.createCharacter(user.uid, trimmed, spellId(spell), jsonObject(profile, "profile"));
    if (!c) throw new BadRequestException("too many characters");
    return c;
  }

  @Delete("characters/:id")
  @ApiOperation({ summary: "Delete a character and its profile" })
  async deleteCharacter(@CurrentUser() user: AuthUser, @Param("id") id: string) {
    await this.players.deleteCharacter(user.uid, id);
    return { ok: true };
  }

  @Get("characters/:id/profile")
  @ApiOperation({ summary: "A character's saved profile" })
  getProfile(@CurrentUser() user: AuthUser, @Param("id") id: string) {
    return this.players.getProfile(user.uid, id);
  }

  @Put("characters/:id/profile")
  @ApiOperation({ summary: "Save a character's profile (game/profile.gd, Profile.to_dict())" })
  @ApiBody({ schema: { type: "object" } })
  async putProfile(@CurrentUser() user: AuthUser, @Param("id") id: string, @Body() profile: unknown) {
    await this.players.putProfile(user.uid, id, jsonObject(profile, "profile"));
    return { ok: true };
  }

  @Delete("account")
  @ApiOperation({ summary: "Erase the player's characters and spells (the Firebase account is deleted by the client)" })
  async deleteAccount(@CurrentUser() user: AuthUser) {
    await this.players.deleteAll(user.uid);
    return { ok: true };
  }

  @Get("spells/:id")
  @ApiOperation({ summary: "A .spell bundle (zip) of the player" })
  @ApiProduces("application/zip")
  async getSpell(@CurrentUser() user: AuthUser, @Param("id") id: string) {
    const bundle = await this.players.getSpell(user.uid, spellId(id));
    if (!bundle) {
      throw new NotFoundException("no such spell");
    }
    return new StreamableFile(bundle, { type: "application/zip" });
  }

  @Put("spells/:id")
  @ApiOperation({ summary: "Save a .spell bundle (zip)" })
  @ApiConsumes("application/octet-stream")
  @ApiBody({ schema: { type: "string", format: "binary" } })
  async putSpell(
    @CurrentUser() user: AuthUser,
    @Param("id") id: string,
    @Body() bundle: unknown,
  ) {
    id = spellId(id);
    if (!Buffer.isBuffer(bundle) || bundle.subarray(0, 2).toString("latin1") !== "PK") {
      throw new BadRequestException("not a .spell bundle");
    }
    await this.players.putSpell(user.uid, id, bundle);
    return { ok: true };
  }
}
