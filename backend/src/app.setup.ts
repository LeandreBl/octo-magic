import { resolve } from "node:path";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { json, raw, type NextFunction, type Request, type Response } from "express";
import { HttpExceptionFilter } from "./common/http-exception.filter";

const MAX_JSON = "512kb";
const MAX_BUNDLE = "4mb";
// Nest routes served outside the /api prefix.
const ROOT_ROUTES = ["health", "api/config"];

/** Everything main.ts and the tests share: routes, bodies, errors. */
export function setupApp(app: NestExpressApplication, webDir?: string) {
  app.setGlobalPrefix("api", { exclude: ROOT_ROUTES });
  app.useGlobalFilters(new HttpExceptionFilter());
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
  const web = webDir || resolve(__dirname, "../../web");
  app.useStaticAssets(web, { extensions: ["html"] });
  app.useStaticAssets(resolve(__dirname, "../../assets"), { prefix: "/assets" });

  // Any other page: the site's 404 (English under /en). Express runs this
  // before Nest's routes, registered at init, so those are let through; an
  // unknown /api route keeps Nest's JSON 404.
  app.use((req: Request, res: Response, next: NextFunction) => {
    const route = req.path.slice(1);
    if (req.method !== "GET" || route === "api" || route.startsWith("api/") || ROOT_ROUTES.includes(route)) return next();
    res.status(404).sendFile(/^en(\/|$)/.test(route) ? "en/404.html" : "404.html", { root: web });
  });
}
