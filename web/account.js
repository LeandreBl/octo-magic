import * as site from "/site.js";

// Same ids, names and goals as Profile.ACHIEVEMENTS (game/profile.gd);
// the names in English for the English site.
const GOALS = {
  first_blood: ["kills", 1], hunter: ["kills", 100], slayer: ["kills", 1000],
  boss: ["bosses", 1], boss3: ["bosses", 3], boss10: ["bosses", 10],
  wave10: ["best_wave", 10], wave20: ["best_wave", 20],
  level10: ["best_level", 10], level20: ["best_level", 20],
  rich: ["gold_total", 1000], scribe: ["scrolls", 5], veteran: ["runs", 10],
};
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
      gold: "Or", runs: "Runs", kills: "Ennemis vaincus", bosses: "Boss vaincus",
      best_wave: "Meilleure vague", best_level: "Meilleur niveau", gold_total: "Or gagné",
      scrolls: "Parchemins trouvés",
    },
    email: "Indique ton adresse e-mail.",
    reset: "E-mail de réinitialisation envoyé.",
    changed: "Mot de passe changé.",
    confirm: "Supprimer définitivement ton compte et ta progression ?",
    noScore: "Aucun score pour l'instant.",
    reached: TEXT.reached,
    noSpell: TEXT.noSpell,
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
      gold: "Gold", runs: "Runs", kills: "Enemies defeated", bosses: "Bosses defeated",
      best_wave: "Best wave", best_level: "Best level", gold_total: "Gold earned",
      scrolls: "Scrolls found",
    },
    email: "Enter your email.",
    reset: "Password reset email sent.",
    changed: "Password changed.",
    confirm: "Permanently delete your account and progress?",
    noScore: "No score yet.",
    reached: "✦ unlocked",
    noSpell: "No forged spell.",
  },
}[site.lang];
const $ = (id) => document.getElementById(id);

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

const login = $("login");
login.onsubmit = action(login, async (button) => {
  const { email, password } = login.elements;
  if (button === "reset") {
    if (!email.value) throw new Error(TEXT.email);
    await site.resetPassword(email.value);
    return TEXT.reset;
  }
  await site.login(email.value, password.value, button === "signup");
}, () => site.session() && location.reload());

const pw = $("password");
pw.onsubmit = action(pw, async () => {
  await site.changePassword(pw.elements.current.value, pw.elements.password.value);
  pw.reset();
  return TEXT.changed;
});

const del = $("delete");
del.onsubmit = action(del, async () => {
  if (!confirm(TEXT.confirm)) return;
  await site.deleteAccount(del.elements.password.value);
}, () => !site.session() && location.reload());

$("logout").onclick = () => {
  site.logout();
  location.reload();
};

function render(p) {
  const stats = { ...(p.stats ?? {}), gold: p.gold ?? 0 };
  $("empty").hidden = Object.keys(p).length > 0;
  $("stats").replaceChildren(...Object.entries(TEXT.stats).map(([k, label]) => {
    const d = document.createElement("div");
    d.className = "stat";
    d.append(Object.assign(document.createElement("b"), { textContent: Number(stats[k] ?? 0).toLocaleString(site.lang) }),
      Object.assign(document.createElement("span"), { textContent: label }));
    return d;
  }));

  const scores = Array.isArray(p.scores) ? p.scores : [];
  $("scores").replaceChildren(...(scores.length ? scores : [null]).map((s) => {
    const tr = document.createElement("tr");
    const cells = s
      ? [s.score, s.wave, s.level, s.kills, s.time ? new Date(s.time * 1000).toLocaleDateString(site.lang) : ""]
      : [TEXT.noScore];
    tr.append(...cells.map((c) => Object.assign(document.createElement("td"), { textContent: c ?? "" })));
    return tr;
  }));

  const reached = p.achievements ?? {};
  $("achievements").replaceChildren(...Object.entries(TEXT.achievements).map(([id, [name, desc]]) => {
    const [stat, goal] = GOALS[id];
    const li = document.createElement("li");
    li.className = id in reached ? "done" : "";
    const progress = id in reached ? TEXT.reached : `${Math.min(stats[stat] ?? 0, goal)} / ${goal}`;
    li.append(Object.assign(document.createElement("b"), { textContent: name }),
      Object.assign(document.createElement("small"), { textContent: `${desc} — ${progress}` }));
    return li;
  }));

  const forged = Array.isArray(p.forged) ? p.forged : [];
  $("forged").replaceChildren(...(forged.length ? forged : [null]).map((f) =>
    Object.assign(document.createElement("li"), {
      textContent: f ? `${f.spell?.name ?? f.id}${f.spell?.description ? ` — ${f.spell.description}` : ""}` : TEXT.noSpell,
    })));
}

const s = site.session();
$(s ? "in" : "out").hidden = false;
if (s) {
  $("email").textContent = s.email;
  try {
    render(await site.api("/api/profile"));
  } catch (err) {
    $("empty").hidden = false;
    $("empty").textContent = err.message;
    if (!site.session()) location.reload();
  }
}
