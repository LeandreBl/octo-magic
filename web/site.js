// The website's login: Firebase email/password through the Identity Toolkit
// REST API, like the game (game/online.gd). The session ({email, refresh})
// lives in localStorage under SESSION, which the web game reads too: logged
// in on the site, logged in in the game, and the other way around.

const SESSION = "octo.session";
const IDENTITY = "https://identitytoolkit.googleapis.com/v1/accounts:";
const SECURE_TOKEN = "https://securetoken.googleapis.com/v1/token?key=";
const LANG = "octo.lang";

// The site in French at the root, in English under /en/: same pages, same
// paths otherwise. The page's <html lang> says which one this is.
export const lang = document.documentElement.lang === "en" ? "en" : "fr";

/** This page's path in the other language. */
function other(path) {
  return lang === "fr" ? `/en${path}` : path.replace(/^\/en/, "") || "/";
}

const TEXT = {
  fr: {
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
    unreachable: "Serveur injoignable.",
    identity: "Serveur d'identité injoignable.",
    expired: "Session expirée, reconnecte-toi.",
    server: "Erreur du serveur",
    login: "Connexion",
  },
  en: {
    EMAIL_EXISTS: "Email already in use.",
    EMAIL_NOT_FOUND: "Invalid email or password.",
    INVALID_PASSWORD: "Invalid email or password.",
    INVALID_LOGIN_CREDENTIALS: "Invalid email or password.",
    INVALID_EMAIL: "Invalid email.",
    MISSING_PASSWORD: "Missing password.",
    WEAK_PASSWORD: "Password too short (6 characters min.).",
    TOO_MANY_ATTEMPTS_TRY_LATER: "Too many attempts, try again later.",
    USER_DISABLED: "Account disabled.",
    CREDENTIAL_TOO_OLD_LOGIN_AGAIN: "Log in again, then retry.",
    unreachable: "Server unreachable.",
    identity: "Identity server unreachable.",
    expired: "Session expired, log in again.",
    server: "Server error",
    login: "Log in",
  },
}[lang];

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
  localStorage.setItem(SESSION, JSON.stringify({ email, refresh }));
}

export function logout() {
  token = "";
  localStorage.removeItem(SESSION);
}

async function key() {
  if (!apiKey) {
    const r = await fetch("/api/config");
    if (!r.ok) throw new Error(TEXT.unreachable);
    apiKey = (await r.json()).firebaseApiKey;
  }
  return apiKey;
}

/** POST to Google's identity API; throws an Error with a message in the page's language. */
async function identity(url, body) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    const code = String(data.error?.message ?? "").split(" ")[0];
    throw new Error(TEXT[code] ?? (code || TEXT.identity));
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
  if (!t) throw new Error(TEXT.expired);
  const r = await fetch(path, { ...init, headers: { ...init.headers, Authorization: `Bearer ${t}` } });
  if (!r.ok) throw new Error(`${TEXT.server} (${r.status}).`);
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

/** Erases the profile and spells on the server, then the Firebase account. */
export async function deleteAccount(password) {
  const t = await fresh(password);
  await api("/api/account", { method: "DELETE" });
  await identity(`${IDENTITY}delete?key=${await key()}`, { idToken: t });
  logout();
}

// The header shows who is logged in.
const who = document.querySelector("[data-who]");
if (who) who.textContent = session()?.email ?? TEXT.login;

// The FR/EN switch in the header leads to this page in the other language
// and remembers the choice. Without a choice, the browser's language picks
// once (not for crawlers: each language has its own indexed URLs).
const lang_switch = document.querySelector("[data-lang]");
if (lang_switch) lang_switch.onclick = () => localStorage.setItem(LANG, lang_switch.dataset.lang);
const wanted = localStorage.getItem(LANG)
  ?? (/bot|crawl|spider|slurp/i.test(navigator.userAgent) ? lang : navigator.language.startsWith("fr") ? "fr" : "en");
localStorage.setItem(LANG, wanted);
if (wanted !== lang) location.replace(other(location.pathname) + location.search + location.hash);
