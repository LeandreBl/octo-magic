import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from "@nestjs/common";
import { join } from "node:path";
import type { Request, Response } from "express";

/** Every error as `{"error": "<message>"}`, the shape the game reads; an
 * unknown page outside /api gets the site's 404 page (`webDir`) instead. */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  constructor(private readonly webDir: string) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    let status = 500;
    let error = "server error";
    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      const message =
        typeof body === "string" ? body : (body as { message?: unknown }).message;
      error = Array.isArray(message) ? message.join(", ") : String(message ?? exception.message);
    } else {
      this.logger.error(exception);
    }
    const req = host.switchToHttp().getRequest<Request>();
    if (status === 404 && req.method === "GET" && !/^\/api(\/|$)/.test(req.path)) {
      const page = /^\/en(\/|$)/.test(req.path) ? "en/404.html" : "404.html";
      return res.status(404).sendFile(join(this.webDir, page));
    }
    if (!res.headersSent) {
      res.status(status).json({ error });
    }
  }
}
