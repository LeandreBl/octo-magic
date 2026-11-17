import { createParamDecorator, ExecutionContext } from "@nestjs/common";

/** The logged-in player, set by FirebaseAuthGuard. */
export type AuthUser = { uid: string; email?: string };

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser =>
    ctx.switchToHttp().getRequest().user,
);
