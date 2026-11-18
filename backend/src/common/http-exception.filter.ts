import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from "@nestjs/common";
import type { Response } from "express";

/** Every error as `{"error": "<message>"}`, the shape the game reads. */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

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
    if (!res.headersSent) {
      res.status(status).json({ error });
    }
  }
}
