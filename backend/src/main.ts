import { NestFactory } from "@nestjs/core";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import { Logger } from "nestjs-pino";
import { AppModule } from "./app.module";
import { setupApp } from "./app.setup";

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
    bodyParser: false,
  });
  app.useLogger(app.get(Logger));
  app.enableShutdownHooks();
  setupApp(app, process.env.WEB_DIR);

  const doc = new DocumentBuilder()
    .setTitle("octo-magic API")
    .setDescription(
      "Firebase login (Authorization: Bearer <ID token>), profiles and " +
        "spells, the forge. The coop lobby is the WebSocket /play " +
        "(src/lobby/lobby.service.ts).",
    )
    .addBearerAuth()
    .build();
  SwaggerModule.setup("api/docs", app, SwaggerModule.createDocument(app, doc));

  await app.listen(Number(process.env.PORT));
}

bootstrap();
