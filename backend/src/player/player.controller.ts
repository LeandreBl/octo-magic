import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Param,
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

function spellId(id: string): string {
  if (!SPELL_ID.test(id)) {
    throw new BadRequestException("invalid spell id");
  }
  return id;
}

@ApiTags("player")
@ApiBearerAuth()
@UseGuards(FirebaseAuthGuard)
@Controller()
export class PlayerController {
  constructor(private readonly players: PlayerService) {}

  @Get("profile")
  @ApiOperation({ summary: "The saved profile ({} for a new player)" })
  getProfile(@CurrentUser() user: AuthUser) {
    return this.players.getProfile(user.uid);
  }

  @Put("profile")
  @ApiOperation({ summary: "Save the profile (game/profile.gd, Profile.to_dict())" })
  @ApiBody({ schema: { type: "object" } })
  async putProfile(@CurrentUser() user: AuthUser, @Body() profile: unknown) {
    if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
      throw new BadRequestException("profile must be an object");
    }
    await this.players.putProfile(user.uid, profile as Prisma.JsonObject);
    return { ok: true };
  }

  @Delete("account")
  @ApiOperation({ summary: "Erase the player's profile and spells (the Firebase account is deleted by the client)" })
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
