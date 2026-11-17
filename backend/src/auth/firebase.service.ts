import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { getApps, initializeApp } from "firebase-admin/app";
import { Auth, DecodedIdToken, getAuth } from "firebase-admin/auth";

@Injectable()
export class FirebaseService {
  private readonly auth: Auth;

  constructor(config: ConfigService) {
    // Verifying ID tokens needs only the project id (Google's public keys),
    // no service account. FIREBASE_AUTH_EMULATOR_HOST switches to the emulator.
    const app =
      getApps()[0] ??
      initializeApp({ projectId: config.getOrThrow("FIREBASE_PROJECT_ID") });
    this.auth = getAuth(app);
  }

  verifyToken(token: string): Promise<DecodedIdToken> {
    return this.auth.verifyIdToken(token);
  }
}
