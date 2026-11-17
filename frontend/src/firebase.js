import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";

// The server hands out the public Firebase settings (no build-time config).
export const auth = fetch("/api/config")
  .then((r) => r.json())
  .then((c) => getAuth(initializeApp({
    apiKey: c.firebaseApiKey,
    projectId: c.firebaseProjectId,
    authDomain: `${c.firebaseProjectId}.firebaseapp.com`,
  })));

/** fetch() on the server's /api as the logged-in user. */
export async function api(user, path, init = {}) {
  const token = await user.getIdToken();
  return fetch(path, { ...init, headers: { ...init.headers, Authorization: `Bearer ${token}` } });
}
