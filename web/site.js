// The website's login: Firebase email/password or Google through the Identity
// Toolkit REST API, like the game (game/online.gd). Google: createAuthUri
// sends to Google, which comes back on /account with ?state=&code=, and
// signInWithIdp turns that into a Firebase session (no SDK). The session ({email, refresh})
// lives in localStorage under SESSION, which the web game reads too: logged
// in on the site, logged in in the game, and the other way around.

const SESSION = "octo.session";
const IDENTITY = "https://identitytoolkit.googleapis.com/v1/accounts:";
const GOOGLE = "octo.google"; // sessionStorage: the Google login under way
const LINK = "octo.link"; // sessionStorage: a Google ID token to link after the password login
const SECURE_TOKEN = "https://securetoken.googleapis.com/v1/token?key=";
const ERRORS = {
  EMAIL_EXISTS: "Adresse déjà utilisée.",
  EMAIL_NOT_FOUND: "Identifiants invalides.",
  INVALID_PASSWORD: "Identifiants invalides.",
  INVALID_LOGIN_CREDENTIALS: "Identifiants invalides.",
  INVALID_EMAIL: "Adresse invalide.",
  MISSING_PASSWORD: "Mot de passe manquant.",
  WEAK_PASSWORD: "Mot de passe trop court (6 caractères min.).",
  TOO_MANY_ATTEMPTS_TRY_LATER: "Trop d'essais, réessaie plus tard.",
  USER_DISABLED: "Compte désactivé.",
  CREDENTIAL_TOO_OLD_LOGIN_AGAIN: "Reconnecte-toi puis réessaie.",
  INVALID_IDP_RESPONSE: "Connexion Google annulée ou refusée.",
};

let apiKey = "";
let token = "";
let expires = 0;

export function session() {
  try {
    const s = JSON.parse(localStorage.getItem(SESSION) || "null");
    return s?.refresh ? s : null;
  } catch {
    return null;
  }
}

function save(email, idToken, refresh, expiresIn) {
  token = idToken;
  expires = Date.now() + Number(expiresIn) * 1000;
  // Keeps the game's other fields (its active character).
  localStorage.setItem(SESSION, JSON.stringify({ ...session(), email, refresh }));
}

export function logout() {
  token = "";
  localStorage.removeItem(SESSION);
}

async function key() {
  if (!apiKey) {
    const r = await fetch("/api/config");
    if (!r.ok) throw new Error("Serveur injoignable.");
    apiKey = (await r.json()).firebaseApiKey;
  }
  return apiKey;
}

/** POST to Google's identity API; throws an Error with a French message. */
async function identity(url, body) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const code = String(data.error?.message ?? "").split(" ")[0];
    throw new Error(ERRORS[code] ?? (code || "Serveur d'identité injoignable."));
  }
  return data;
}

/** Logs in, or creates the account. */
export async function login(email, password, create = false) {
  const d = await identity(`${IDENTITY}${create ? "signUp" : "signInWithPassword"}?key=${await key()}`, {
    email: email.trim(),
    password,
    returnSecureToken: true,
  });
  save(d.email, d.idToken, d.refreshToken, d.expiresIn);
  const link = sessionStorage.getItem(LINK);
  if (link) {
    sessionStorage.removeItem(LINK);
    const l = await idp({ idToken: d.idToken, postBody: `id_token=${link}&providerId=google.com`, requestUri: location.origin });
    save(l.email, l.idToken, l.refreshToken, l.expiresIn);
  }
}

async function idp(body) {
  return identity(`${IDENTITY}signInWithIdp?key=${await key()}`, { returnSecureToken: true, ...body });
}

/** Leaves for Google's login; back on /account, finishGoogle() ends it. then: where to go after. */
export async function google(then = "") {
  const d = await identity(`${IDENTITY}createAuthUri?key=${await key()}`, {
    providerId: "google.com",
    continueUri: `${location.origin}/account`,
  });
  sessionStorage.setItem(GOOGLE, JSON.stringify({ sessionId: d.sessionId, then, email: session()?.email }));
  location.assign(d.authUri);
}

/** Back from Google: logs in and returns the `then` given to google(); null when not back from Google. */
export async function finishGoogle() {
  const pending = JSON.parse(sessionStorage.getItem(GOOGLE) || "null");
  if (!pending || !new URLSearchParams(location.search).has("state")) return null;
  sessionStorage.removeItem(GOOGLE);
  const requestUri = location.href;
  history.replaceState(null, "", location.pathname); // the code is single use
  const d = await idp({ requestUri, sessionId: pending.sessionId, returnIdpCredential: true });
  if (d.needConfirmation) {
    // A password account has this email and Google can't take it over: link it after the password login.
    sessionStorage.setItem(LINK, d.oauthIdToken);
    throw new Error("Cette adresse a déjà un compte : connecte-toi avec ton mot de passe, Google y sera lié.");
  }
  // A re-login for the account deletion must be the same account.
  if (pending.email && d.email !== pending.email) throw new Error(`Connecte-toi avec le compte Google ${pending.email}.`);
  save(d.email, d.idToken, d.refreshToken, d.expiresIn);
  return pending.then;
}

/** The account's ways to log in: "password", "google.com". */
export async function providers() {
  const d = await identity(`${IDENTITY}lookup?key=${await key()}`, { idToken: await idToken() });
  return (d.users?.[0]?.providerUserInfo ?? []).map((p) => p.providerId);
}

export async function resetPassword(email) {
  await identity(`${IDENTITY}sendOobCode?key=${await key()}`, { requestType: "PASSWORD_RESET", email: email.trim() });
}

/** The ID token, refreshed when needed; "" when logged out. */
export async function idToken() {
  const s = session();
  if (!s) return "";
  if (token && Date.now() < expires - 60_000) return token;
  const r = await fetch(SECURE_TOKEN + (await key()), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: s.refresh }),
  });
  if (r.status === 400) logout(); // revoked or expired
  if (!r.ok) return "";
  const d = await r.json();
  save(s.email, d.id_token, d.refresh_token, d.expires_in);
  return token;
}

/** fetch() on the server's API with the login. */
export async function api(path, init = {}) {
  const t = await idToken();
  if (!t) throw new Error("Session expirée, reconnecte-toi.");
  const r = await fetch(path, { ...init, headers: { ...init.headers, Authorization: `Bearer ${t}` } });
  if (!r.ok) throw new Error(`Erreur du serveur (${r.status}).`);
  return r.json();
}

/** Logs in again with the password: Google requires a recent login for these. */
async function fresh(password) {
  await login(session().email, password);
  return token;
}

export async function changePassword(current, password) {
  const d = await identity(`${IDENTITY}update?key=${await key()}`, {
    idToken: await fresh(current),
    password,
    returnSecureToken: true,
  });
  save(session().email, d.idToken, d.refreshToken, d.expiresIn);
}

/** Erases the profile and spells on the server, then the Firebase account.
 * Without a password, right after a Google login (finishGoogle). */
export async function deleteAccount(password) {
  const t = password ? await fresh(password) : token;
  await api("/api/account", { method: "DELETE" });
  await identity(`${IDENTITY}delete?key=${await key()}`, { idToken: t });
  logout();
}

// The header shows who is logged in.
const who = document.querySelector("[data-who]");
if (who) who.textContent = session()?.email ?? "Connexion";
