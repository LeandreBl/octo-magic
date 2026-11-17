import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Link, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { onAuthStateChanged } from "firebase/auth";
import { auth } from "./firebase.js";
import { Account, Landing, Login, Play, UserContext, useUser } from "./pages.jsx";
import "./style.css";

function App() {
  const [user, setUser] = useState(undefined);
  useEffect(() => {
    let off = () => {};
    auth.then((a) => { off = onAuthStateChanged(a, setUser); }, () => setUser(null));
    return () => off();
  }, []);
  return (
    <UserContext.Provider value={user}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Page><Landing /></Page>} />
          <Route path="/login" element={<Page><Login /></Page>} />
          <Route path="/account" element={<Page><LoggedIn><Account /></LoggedIn></Page>} />
          <Route path="/play" element={<LoggedIn><Play /></LoggedIn>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
    </UserContext.Provider>
  );
}

function Page({ children }) {
  const user = useUser();
  return (
    <>
      <nav>
        <Link to="/" className="brand">Octo Magic</Link>
        {user ? <Link to="/account">Mon compte</Link> : <Link to="/login">Connexion</Link>}
        <Link to="/play" className="button">Jouer</Link>
      </nav>
      <main>{children}</main>
      <footer><a href="/terms">Conditions</a> · <a href="/privacy">Confidentialité</a></footer>
    </>
  );
}

/** Logged-out visitors go to /login, then come back. */
function LoggedIn({ children }) {
  const user = useUser();
  const { pathname } = useLocation();
  if (user === undefined) return <p className="center">Chargement…</p>;
  return user ? children : <Navigate to="/login" replace state={{ next: pathname }} />;
}

createRoot(document.getElementById("root")).render(<StrictMode><App /></StrictMode>);
