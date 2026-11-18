import * as site from "/site.js";

// Same ids and goals as Profile.ACHIEVEMENTS (game/profile.gd).
const GOALS = {
  first_blood: ["kills", 1], hunter: ["kills", 100], slayer: ["kills", 1000],
  boss: ["bosses", 1], boss3: ["bosses", 3], boss10: ["bosses", 10],
  wave10: ["best_wave", 10], wave20: ["best_wave", 20],
  level10: ["best_level", 10], level20: ["best_level", 20],
  rich: ["gold_total", 1000], scribe: ["scrolls", 5], veteran: ["runs", 10],
};
// Stat, then the icon of its tile (assets/icons).
const STATS = [
  ["gold", "gold"], ["runs", "spark"], ["kills", "meteor_rain"], ["bosses", "black_hole"],
  ["best_wave", "blizzard"], ["best_level", "staff_crystal"], ["gold_total", "ring_gold"], ["scrolls", "scroll"],
];
// Spell elements (spell/spell.gd ELEMENTS): the icon of a spell card.
const ELEMENT_ICON = { fire: "fire_nova", ice: "frost_shard", lightning: "storm", poison: "toxic_cloud", arcane: "arcane_missiles", physical: "meteor_rain" };
const TEXT = {
  fr: {
    achievements: {
      first_blood: ["Premier sang", "Vaincre un ennemi"],
      hunter: ["Chasseur", "Vaincre 100 ennemis"],
      slayer: ["Fléau", "Vaincre 1000 ennemis"],
      boss: ["Tueur de géants", "Vaincre un boss"],
      boss3: ["Chasseur de géants", "Vaincre 3 boss"],
      boss10: ["Fléau des géants", "Vaincre 10 boss"],
      wave10: ["Endurant", "Atteindre la vague 10"],
      wave20: ["Inarrêtable", "Atteindre la vague 20"],
      level10: ["Érudit", "Atteindre le niveau 10 en une run"],
      level20: ["Archimage", "Atteindre le niveau 20 en une run"],
      rich: ["Fortuné", "Gagner 1000 pièces d'or au total"],
      scribe: ["Scribe", "Trouver 5 parchemins vierges"],
      veteran: ["Vétéran", "Jouer 10 runs"],
    },
    stats: {
      gold: "Or", runs: "Runs", kills: "Ennemis vaincus", bosses: "Boss vaincus", best_wave: "Meilleure vague",
      best_level: "Meilleur niveau", gold_total: "Or gagné", scrolls: "Parchemins trouvés",
    },
    elements: { fire: "Feu", ice: "Glace", lightning: "Foudre", poison: "Poison", arcane: "Arcane", physical: "Physique" },
    modes: { signin: "Entrer dans le donjon", signup: "Créer mon compte", reset: "Envoyer le lien" },
    email: "Indique ton adresse e-mail.",
    reset: "Lien envoyé ! Jette un œil à ta boîte mail.",
    changed: "Mot de passe changé.",
    confirm: "Supprimer définitivement ton compte et ta progression ?",
    noScore: "Aucun score pour l'instant. La première run t'attend !",
    reached: "obtenu",
    unlocked: (n, total) => `${n} sur ${total} obtenus`,
    primary: "Sort principal", secondary: "Sort secondaire", equip: "Équipable dans le jeu",
    blankFirst: "Un parchemin attend un mot", blankMore: "Un nouveau parchemin ?",
    blankText: "Arrache des parchemins vierges aux boss, puis grave-y un mot dans le jeu.",
    blankButton: "Aller au donjon",
  },
  en: {
    achievements: {
      first_blood: ["First Blood", "Defeat an enemy"],
      hunter: ["Hunter", "Defeat 100 enemies"],
      slayer: ["Scourge", "Defeat 1000 enemies"],
      boss: ["Giant Slayer", "Defeat a boss"],
      boss3: ["Giant Hunter", "Defeat 3 bosses"],
      boss10: ["Bane of Giants", "Defeat 10 bosses"],
      wave10: ["Enduring", "Reach wave 10"],
      wave20: ["Unstoppable", "Reach wave 20"],
      level10: ["Scholar", "Reach level 10 in one run"],
      level20: ["Archmage", "Reach level 20 in one run"],
      rich: ["Wealthy", "Earn 1000 gold in total"],
      scribe: ["Scribe", "Find 5 blank scrolls"],
      veteran: ["Veteran", "Play 10 runs"],
    },
    stats: {
      gold: "Gold", runs: "Runs", kills: "Enemies defeated", bosses: "Bosses defeated", best_wave: "Best wave",
      best_level: "Best level", gold_total: "Gold earned", scrolls: "Scrolls found",
    },
    elements: { fire: "Fire", ice: "Ice", lightning: "Lightning", poison: "Poison", arcane: "Arcane", physical: "Physical" },
    modes: { signin: "Enter the dungeon", signup: "Create my account", reset: "Send the link" },
    email: "Enter your email.",
    reset: "Link sent! Check your inbox.",
    changed: "Password changed.",
    confirm: "Permanently delete your account and progress?",
    noScore: "No score yet. Your first run awaits!",
    reached: "unlocked",
    unlocked: (n, total) => `${n} of ${total} unlocked`,
    primary: "Primary spell", secondary: "Secondary spell", equip: "Ready to equip in the game",
    blankFirst: "A scroll awaits a word", blankMore: "A new scroll?",
    blankText: "Wrest blank scrolls from the bosses, then carve a word on them in the game.",
    blankButton: "To the dungeon",
  },
}[site.lang];
const TOTAL = Object.keys(GOALS).length;
const SVG = "http://www.w3.org/2000/svg";
const $ = (id) => document.getElementById(id);
const num = (n) => Number(n ?? 0).toLocaleString(site.lang);
// Where to go once logged in (?then=/game or /en/game from the game's guard); same-site paths only.
const next = new URLSearchParams(location.search).get("then");
const then = /^\/[^/\\]/.test(next ?? "") ? next : "";

/** document.createElement with properties and children (null children skipped). */
function el(tag, props = {}, ...children) {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children.filter((c) => c != null));
  return e;
}
const icon = (name) => el("img", { className: "pixel", src: `/assets/icons/${name}.png`, alt: "" });
/** The badge of an achievement: a check when reached, a lock otherwise. */
function badge(done) {
  const svg = document.createElementNS(SVG, "svg");
  for (const [k, v] of Object.entries({ width: 20, height: 20, viewBox: "0 0 20 20", "aria-hidden": "true" })) svg.setAttribute(k, v);
  svg.innerHTML = done
    ? '<path d="M4 10.5 L8 14.5 L16 6" fill="none" stroke="#1a1206" stroke-width="3" stroke-linecap="square"/>'
    : '<rect x="4" y="9" width="12" height="8" fill="none" stroke="#8f86ad" stroke-width="2"/><path d="M7 9 V6 a3 3 0 0 1 6 0 V9" fill="none" stroke="#8f86ad" stroke-width="2"/>';
  return el("span", { className: "badge" }, svg);
}

// Runs an async form action: button disabled meanwhile, message after.
function action(form, run, done) {
  const msg = form.querySelector(".msg");
  return async (e) => {
    e.preventDefault();
    const buttons = form.querySelectorAll("button");
    buttons.forEach((b) => (b.disabled = true));
    msg.className = "msg";
    msg.textContent = "";
    try {
      const ok = await run(e.submitter?.name);
      msg.className = "msg ok";
      msg.textContent = ok ?? "";
      done?.();
    } catch (err) {
      msg.className = "msg error";
      msg.textContent = err.message;
    }
    buttons.forEach((b) => (b.disabled = false));
  };
}

// --- Logged out: one form, three modes (log in, sign up, password reset). ---
const login = $("login");
const submit = $("submit");
function mode(m) {
  submit.name = m;
  submit.textContent = TEXT.modes[m];
  const pw = login.elements.password;
  pw.autocomplete = m === "signup" ? "new-password" : "current-password";
  pw.required = m !== "reset";
  $("pw-field").hidden = m === "reset";
  $("pw-hint").hidden = m !== "signup";
  $("forgot").hidden = m !== "signin";
  $("tabs").hidden = m === "reset";
  $("google-block").hidden = m === "reset";
  $("reset-head").hidden = m !== "reset";
  $("legal").hidden = m !== "signup";
  $("tabs").querySelectorAll("button").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.mode === m)));
  login.querySelector(".msg").textContent = "";
}
document.querySelectorAll("#out [data-mode]").forEach((b) => (b.onclick = () => mode(b.dataset.mode)));

login.onsubmit = action(login, async (button) => {
  const { email, password } = login.elements;
  if (button === "reset") {
    if (!email.value) throw new Error(TEXT.email);
    await site.resetPassword(email.value);
    return TEXT.reset;
  }
  await site.login(email.value, password.value, button === "signup");
}, () => site.session() && (then ? location.replace(then) : location.reload()));

// --- Logged in ---
const pw = $("password");
pw.onsubmit = action(pw, async () => {
  await site.changePassword(pw.elements.current.value, pw.elements.password.value);
  pw.reset();
  return TEXT.changed;
});

const del = $("delete");
del.onsubmit = action(del, async () => {
  if (!confirm(TEXT.confirm)) return;
  if (del.dataset.google) return site.google("delete"); // deleted back on this page
  await site.deleteAccount(del.elements.password.value);
}, () => !site.session() && location.reload());

$("google").onclick = async () => {
  try {
    await site.google(then);
  } catch (err) {
    say(login, err);
  }
};

// An error outside a form submit (Google login, deletion after it).
function say(form, err) {
  const msg = form.querySelector(".msg");
  msg.className = "msg error";
  msg.textContent = err.message;
}

$("logout").onclick = () => {
  site.logout();
  location.reload();
};

function render(p, character) {
  const stats = { ...(p.stats ?? {}), gold: p.gold ?? 0 };
  if (character?.name) $("mage").textContent = character.name;
  $("gold").textContent = num(stats.gold);
  $("gold-pill").hidden = false;
  $("empty").hidden = Object.keys(p).length > 0;

  $("stats").replaceChildren(...STATS.map(([k, ic]) =>
    el("div", { className: "stat" }, el("span", { className: "slot" }, icon(ic)),
      el("span", {}, el("b", { textContent: num(stats[k]) }), el("span", { textContent: TEXT.stats[k] })))));

  const scores = Array.isArray(p.scores) ? p.scores : [];
  $("scores").replaceChildren(...(scores.length
    ? scores.map((s, i) => el("tr", {},
        el("td", {}, el("span", { className: `rank r${i + 1}`, textContent: i + 1 })),
        el("td", { className: "score", textContent: num(s.score) }),
        el("td", { textContent: s.wave ?? "" }),
        el("td", { textContent: s.level ?? "" }),
        el("td", { textContent: num(s.kills) }),
        el("td", { className: "date", textContent: s.time ? new Date(s.time * 1000).toLocaleDateString(site.lang) : "" })))
    : [el("tr", {}, el("td", { className: "none", colSpan: 6, textContent: TEXT.noScore }))]));

  // Reached first, then the closest to their goal.
  const reached = p.achievements ?? {};
  const list = Object.entries(GOALS).map(([id, [stat, goal]]) => {
    const [name, desc] = TEXT.achievements[id];
    const done = id in reached;
    const value = Math.min(stats[stat] ?? 0, goal);
    const li = el("li", { className: done ? "done" : "" }, badge(done), el("span", { className: "body" },
      el("b", { textContent: name }),
      el("small", { textContent: `${desc} · ${done ? TEXT.reached : `${num(value)} / ${num(goal)}`}` }),
      done ? null : el("span", { className: "bar thin" }, el("span", { style: `width: ${Math.round((value / goal) * 100)}%` }))));
    return { li, rank: done ? 2 : value / goal };
  }).sort((a, b) => b.rank - a.rank);
  const count = Object.keys(GOALS).filter((id) => id in reached).length;
  $("achievements").replaceChildren(...list.map((a) => a.li));
  $("done-count").textContent = `${count} / ${TOTAL}`;
  $("done-label").textContent = TEXT.unlocked(count, TOTAL);
  $("done-bar").style.width = `${Math.round((count / TOTAL) * 100)}%`;

  // Spells as scrolls, then a blank one that sends to the game.
  const forged = Array.isArray(p.forged) ? p.forged : [];
  $("forged").replaceChildren(
    ...forged.map((f) => {
      const s = f.spell ?? {};
      const element = TEXT.elements[s.element];
      return el("li", { className: "parchment" },
        el("header", {}, el("span", { textContent: s.name ?? f.id }), element ? el("span", { className: "chip", textContent: element }) : null),
        s.description ? el("p", { style: "margin: 0; font-size: 1rem; line-height: 1.5", textContent: s.description }) : null,
        el("span", { className: "spell-card" }, el("span", { className: "slot" }, icon(ELEMENT_ICON[s.element] ?? "scroll")),
          el("span", {}, el("b", { textContent: f.slot === "secondary" ? TEXT.secondary : TEXT.primary }), el("small", { textContent: TEXT.equip }))));
    }),
    el("li", { className: "blank dashed" }, icon("scroll"),
      el("b", { textContent: forged.length ? TEXT.blankMore : TEXT.blankFirst }),
      el("span", { textContent: TEXT.blankText }),
      el("a", { className: "btn btn-sm", href: `${site.base}/game`, textContent: TEXT.blankButton })));
}

// Back from Google (?state=&code=), or sent here by the web game to log in with Google (?google).
try {
  const then = await site.finishGoogle();
  if (then === "delete") {
    await site.deleteAccount();
  } else if (then) {
    location.replace(then);
  } else if (then === null && !site.session() && new URLSearchParams(location.search).has("google")) {
    await site.google(`${site.base}/game`);
  }
} catch (err) {
  say(site.session() ? del : login, err);
}

const s = site.session();
$(s ? "in" : "out").hidden = false;
if (s) {
  $("email").textContent = s.email;
  // A Google-only account has no password: no change, and the deletion re-logs in with Google.
  site.providers().then((p) => {
    if (p.includes("password")) return;
    pw.hidden = true;
    del.dataset.google = "1";
    $("delete-pw").remove();
    del.querySelector("[data-google]").hidden = false;
  }).catch(() => {});
  try {
    // The game's active character, else the first one.
    const chars = await site.api("/api/characters");
    const c = chars.find((c) => c.id === s.character) ?? chars[0];
    render(c ? await site.api(`/api/characters/${c.id}/profile`) : {}, c);
  } catch (err) {
    $("empty").hidden = false;
    $("empty-text").textContent = err.message;
    if (!site.session()) location.reload();
  }
}
