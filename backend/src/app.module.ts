import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { LoggerModule } from "nestjs-pino";
import { AppController } from "./app.controller";
import { AuthModule } from "./auth/auth.module";
import { validateEnv } from "./common/env.validation";
import { ForgeModule } from "./forge/forge.module";
import { LobbyModule } from "./lobby/lobby.module";
import { PlayerModule } from "./player/player.module";
import { PrismaModule } from "./prisma/prisma.module";

const dev = process.env.NODE_ENV !== "production";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.NODE_ENV === "test" ? "silent" : dev ? "debug" : "info",
        transport: dev
          ? {
              target: "pino-pretty",
              options: { colorize: true, singleLine: true, ignore: "pid,hostname,req,res,responseTime" },
            }
          : undefined,
        // Static files of the web game are not worth a line each.
        autoLogging: { ignore: (req) => !req.url?.startsWith("/api/") },
        customLogLevel: (_req, res, err) =>
          err || res.statusCode >= 500 ? "error" : res.statusCode >= 400 ? "warn" : "info",
        customSuccessMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
        customErrorMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
        serializers: { req: () => undefined, res: () => undefined },
      },
    }),
    PrismaModule,
    AuthModule,
    PlayerModule,
    ForgeModule,
    LobbyModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
