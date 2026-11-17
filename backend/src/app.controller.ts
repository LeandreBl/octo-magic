import { Controller, Get } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ApiOperation, ApiTags } from "@nestjs/swagger";

@ApiTags("app")
@Controller()
export class AppController {
  constructor(private readonly config: ConfigService) {}

  @Get("health")
  @ApiOperation({ summary: "Liveness, for the container healthcheck" })
  health() {
    return { ok: true };
  }

  @Get("api/config")
  @ApiOperation({ summary: "Public settings the game reads before logging in" })
  publicConfig() {
    // The Firebase web API key is public: it ships in every client.
    return { firebaseApiKey: this.config.get("FIREBASE_API_KEY") ?? "" };
  }
}
