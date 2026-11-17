import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { FirebaseService } from "./firebase.service";

/** Requires `Authorization: Bearer <Firebase ID token>`; sets request.user. */
@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(private readonly firebase: FirebaseService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const match = /^Bearer (.+)$/.exec(request.headers.authorization ?? "");
    if (!match) {
      throw new UnauthorizedException("missing token");
    }
    try {
      const { uid, email } = await this.firebase.verifyToken(match[1]);
      request.user = { uid, email };
    } catch {
      throw new UnauthorizedException("invalid token");
    }
    return true;
  }
}
