import { resolve } from "node:path";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { json, raw, type NextFunction, type Request, type Response } from "express";
import { HttpExceptionFilter } from "./common/http-exception.filter";

const MAX_JSON = "512kb";
const MAX_BUNDLE = "4mb";

/** Everything main.ts and the tests share: routes, bodies, errors. */
export function setupApp(app: NestExpressApplication, webDir?: string) {
  app.setGlobalPrefix("api", { exclude: ["health", "api/config"] });
  const web = webDir || resolve(__dirname, "../../web");
  app.useGlobalFilters(new HttpExceptionFilter(web));
  app.enableCors();

  // Bodies per route, whatever the Content-Type the game sends: the profile
  // is JSON, spells are zips, the forge's requests pass through untouched.
  const any = () => true;
  app.use("/api/characters", json({ limit: MAX_JSON, type: any }));
  app.use("/api/forge", raw({ limit: MAX_JSON, type: any }));
  app.use("/api/spells", raw({ limit: MAX_BUNDLE, type: any }));
  app.use((err: { status?: number; type?: string }, _req: Request, res: Response, next: NextFunction) => {
    if (!err.type) return next(err);
    const tooLarge = err.type === "entity.too.large";
    res.status(err.status ?? 400).json({ error: tooLarge ? "body too large" : "invalid JSON" });
  });

  // The website (web/: landing, account, /terms, /privacy, the game page)
  // and, in the image, the game's web export under /godot. Locally (no
  // WEB_DIR) the repository's web/ and assets/, from src/ or dist/ alike.
  app.useStaticAssets(web, { extensions: ["html"] });
  app.useStaticAssets(resolve(__dirname, "../../assets"), { prefix: "/assets" });
}
