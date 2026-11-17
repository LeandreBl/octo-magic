import { createContext, useContext, useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  createUserWithEmailAndPassword, GoogleAuthProvider, signInWithEmailAndPassword, signInWithPopup, signOut,
} from "firebase/auth";
import { api, auth } from "./firebase.js";

export const UserContext = createContext(undefined);
/** The Firebase user: undefined while loading, null when logged out. */
export const useUser = () => useContext(UserContext);

const ICONS = ["fire_nova", "frost_ring", "arcane_missiles", "meteor_rain", "black_hole", "blizzard"];
const icon = (name) => new URL(`../../assets/icons/${name}.png`, import.meta.url).href;

export function Landing() {
  return (
    <>
      <section className="hero">
        <h1>Octo Magic</h1>
        <p>Crée, combine et lance tes sorts pour conquérir le donjon.</p>
        <Link to="/play" className="button big">Jouer</Link>
      </section>
      <section className="features">
        <Feature title="Écris tes sorts">Une langue morte sur un parchemin vierge : la forge en fait un sort unique.</Feature>
        <Feature title="Survis aux vagues">Monte de niveau, choisis tes améliorations, affronte les boss.</Feature>
        <Feature title="Joue à plusieurs">Jusqu'à quatre mages en coop, un simple code de salon suffit.</Feature>
        <Feature title="Sauvegarde en ligne">Ton or, ton équipement et tes sorts te suivent sur chaque appareil.</Feature>
      </section>
      <div className="icons">{ICONS.map((n) => <img key={n} src={icon(n)} alt="" />)}</div>
    </>
  );
}

const Feature = ({ title, children }) => <article><h3>{title}</h3><p>{children}</p></article>;

const ERRORS = {
  "auth/invalid-credential": "Identifiants invalides.",
  "auth/invalid-email": "Adresse invalide.",
  "auth/email-already-in-use": "Adresse déjà utilisée.",
  "auth/weak-password": "Mot de passe trop court (6 caractères min.).",
  "auth/too-many-requests": "Trop d'essais, réessaie plus tard.",
  "auth/popup-closed-by-user": "",
};

export function Login() {
  const user = useUser();
  const navigate = useNavigate();
  const next = useLocation().state?.next ?? "/account";
  const [create, setCreate] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => { if (user) navigate(next, { replace: true }); }, [user, next, navigate]);

  async function run(login) {
    setBusy(true);
    setError("");
    try { await login(await auth); } catch (e) { setError(ERRORS[e.code] ?? "Connexion impossible."); }
    setBusy(false);
  }
  function submit(e) {
    e.preventDefault();
    const { email, password } = Object.fromEntries(new FormData(e.target));
    run((a) => (create ? createUserWithEmailAndPassword : signInWithEmailAndPassword)(a, email, password));
  }

  return (
    <section className="card">
      <h2>{create ? "Créer un compte" : "Connexion"}</h2>
      <form onSubmit={submit}>
        <input name="email" type="email" placeholder="Adresse e-mail" autoComplete="email" required />
        <input name="password" type="password" placeholder="Mot de passe" minLength={6} required
          autoComplete={create ? "new-password" : "current-password"} />
        {error && <p className="error">{error}</p>}
        <button disabled={busy}>{create ? "Créer le compte" : "Se connecter"}</button>
      </form>
      <button className="secondary" disabled={busy} onClick={() => run((a) => signInWithPopup(a, new GoogleAuthProvider()))}>
        Continuer avec Google
      </button>
      <p>
        {create ? "Déjà un compte ? " : "Pas encore de compte ? "}
        <a href="#" onClick={(e) => { e.preventDefault(); setCreate(!create); setError(""); }}>
          {create ? "Se connecter" : "En créer un"}
        </a>
      </p>
    </section>
  );
}

export function Account() {
  const user = useUser();
  const [profile, setProfile] = useState(undefined);
  useEffect(() => {
    api(user, "/api/profile").then((r) => (r.ok ? r.json() : null)).then(setProfile, () => setProfile(null));
  }, [user]);
  const s = profile?.stats ?? {};
  return (
    <section className="card">
      <h2>Mon compte</h2>
      <p>{user.email}</p>
      {profile === undefined ? <p>Chargement de la sauvegarde…</p>
        : profile === null ? <p className="error">Sauvegarde injoignable.</p>
        : !profile.stats ? <p>Pas encore de sauvegarde : lance une partie !</p>
        : (
          <dl>
            <dt>Or</dt><dd>{profile.gold ?? 0}</dd>
            <dt>Parties</dt><dd>{s.runs ?? 0}</dd>
            <dt>Meilleure vague</dt><dd>{s.best_wave ?? 0}</dd>
            <dt>Ennemis vaincus</dt><dd>{s.kills ?? 0}</dd>
            <dt>Boss vaincus</dt><dd>{s.bosses ?? 0}</dd>
            <dt>Sorts forgés</dt><dd>{profile.forged?.length ?? 0}</dd>
          </dl>
        )}
      <Link to="/play" className="button big">Jouer</Link>
      <button className="secondary" onClick={async () => signOut(await auth)}>Se déconnecter</button>
    </section>
  );
}

/** The game's web export, logged in with the page's account: game/online.gd
 * reads window.octoSession from its parent and syncs the save with the server. */
export function Play() {
  const user = useUser();
  window.octoSession = { email: user.email, refresh: user.refreshToken };
  return (
    <>
      <iframe className="game" src="/game/index.html" title="Octo Magic" allow="fullscreen; gamepad" autoFocus />
      <Link to="/account" className="back">← Compte</Link>
    </>
  );
}
