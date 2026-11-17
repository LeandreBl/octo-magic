import {
  BadGatewayException,
  ForbiddenException,
  Body,
  Controller,
  Get,
  NotFoundException,
  Param,
  Post,
  Res,
  UseGuards,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ApiBearerAuth, ApiBody, ApiOperation, ApiTags } from "@nestjs/swagger";
import type { Response } from "express";
import { AuthUser, CurrentUser } from "../auth/current-user.decorator";
import { FirebaseAuthGuard } from "../auth/firebase-auth.guard";

/** The forge (server/forge.py), behind the login: its replies pass through. */
@ApiTags("forge")
@ApiBearerAuth()
@UseGuards(FirebaseAuthGuard)
@Controller("forge")
export class ForgeController {
  private readonly forgeUrl?: string;
  /** Who may forge, lowercase; null: every logged-in player. */
  private readonly forgeEmails: string[] | null;

  constructor(config: ConfigService) {
    this.forgeUrl = config.get("FORGE_URL");
    const emails = config.get<string>("FORGE_EMAILS");
    this.forgeEmails = emails ? emails.toLowerCase().split(",").map((e) => e.trim()) : null;
  }

  @Post()
  @ApiOperation({ summary: "Start forging a spell: {job}" })
  @ApiBody({ schema: { type: "object" } })
  start(@CurrentUser() user: AuthUser, @Body() body: unknown, @Res() res: Response) {
    return this.relay(user, "/forge", res, "POST", body);
  }

  @Get(":job")
  @ApiOperation({ summary: "A forge job: its state, then the spell" })
  job(@CurrentUser() user: AuthUser, @Param("job") job: string, @Res() res: Response) {
    if (!/^[\w-]+$/.test(job)) {
      throw new NotFoundException("not found");
    }
    return this.relay(user, `/forge/${job}`, res, "GET");
  }

  private async relay(
    user: AuthUser,
    path: string,
    res: Response,
    method: "GET" | "POST",
    body?: unknown,
  ) {
    if (!this.forgeUrl) {
      throw new NotFoundException("not found");
    }
    if (this.forgeEmails && !this.forgeEmails.includes(String(user.email).toLowerCase())) {
      throw new ForbiddenException("forge not open to this account");
    }
    const reply = await fetch(this.forgeUrl + path, {
      method,
      headers: { "Content-Type": "application/json" },
      body: Buffer.isBuffer(body) ? new Uint8Array(body) : undefined,
    }).catch(() => {
      throw new BadGatewayException("forge unreachable");
    });
    res
      .status(reply.status)
      .type(reply.headers.get("content-type") ?? "application/json")
      .send(Buffer.from(await reply.arrayBuffer()));
  }
}
