// The rune gate: the loading screen of the web game (web/godot-shell.html).
// A ring of 24 runes that dials like a stargate: for each step of the
// loading it spins (alternating ways) to a rune, the top chevron engages,
// and the next of the 9 chevrons locks in gold. The 9th opens the portal
// and the gate fades out on the game.
//
//   const g = runeGate(document.body);
//   g.progress(0.4);      // 0..1, the download: chevrons 1..7 follow it
//   await g.finish();     // the last chevrons, the portal, then removed
//   g.fail(message);      // red chevrons, the message and a retry button
//
// Self-contained (its CSS is injected), in the site's Grimoire Arcade look.

const SVG = "http://www.w3.org/2000/svg";
const CHEVRONS = 9;
const DOWNLOAD_CHEVRONS = 7; // the 8th when the engine runs, the 9th opens
const RUNES = 24;
const STEP = 360 / RUNES;

// Elder Futhark runes, drawn as strokes in a 12 x 20 box centered on 0, 0.
const GLYPHS = [
  "M-3 10V-10M-3-4L4-9M-3 2L4-3", // fehu
  "M-4 10V-10L4-4V10", // uruz
  "M-3-10V10M-3-5L3 0L-3 5", // thurisaz
  "M-3 10V-10L4-5M-3-4L4 1", // ansuz
  "M-4 10V-10L3-5L-4 0L4 10", // raidho
  "M3-8L-3-2L3 4", // kaunan
  "M-5-8L5 8M5-8L-5 8", // gebo
  "M-3 10V-10L3-5L-3 0", // wunjo
  "M-4-10V10M4-10V10M-4-4L4 4", // hagalaz
  "M0-10V10M-4-3L4 3", // naudiz
  "M0-10V10", // isa
  "M-1-8L-5-2L-1 4M1-4L5 2L1 8", // jera
  "M0-10V10M0-10L4-6M0 10L-4 6", // eihwaz
  "M-4-10V10M-4-10L2-6M-4 10L2 6M2-6V-3M2 6V3", // perthro
  "M0 10V-10M0-2L-5-8M0-2L5-8", // algiz
  "M3-10L-3-3L3 3L-3 10", // sowilo
  "M0 10V-10M-5-4L0-10L5-4", // tiwaz
  "M-4-10V10M-4-10L3-5L-4 0L3 5L-4 10", // berkano
  "M-4 10V-10L0-4L4-10V10", // ehwaz
  "M-4 10V-10L4 0M4 10V-10L-4 0", // mannaz
  "M-3 10V-10L4-4", // laguz
  "M0-8L5-2L0 4L-5-2Z", // ingwaz
  "M-5-8V8L5-8V8L-5-8", // dagaz
  "M-5 10L4 0L0-9L-4 0L5 10", // othala
];

const TEXT = {
  fr: {
    dial: "Composition de l'adresse du donjon…",
    steps: [
      "Tracé du premier glyphe…", "Alignement des astres…", "Éveil des runes anciennes…",
      "Déroulement des parchemins…", "Invocation des monstres…", "Aiguisage des bâtons…",
      "Réveil des boss…", "Stabilisation du vortex…", "Le portail s'ouvre !",
    ],
    locked: (n) => `Chevron ${n} verrouillé`,
    none: "Aucun chevron verrouillé",
    retry: "Réessayer",
    gate: "Chargement du jeu",
  },
  en: {
    dial: "Dialing the dungeon's address…",
    steps: [
      "Tracing the first glyph…", "Aligning the stars…", "Waking the ancient runes…",
      "Unrolling the scrolls…", "Summoning the monsters…", "Sharpening the staves…",
      "Rousing the bosses…", "Stabilizing the vortex…", "The portal opens!",
    ],
    locked: (n) => `Chevron ${n} locked`,
    none: "No chevron locked",
    retry: "Try again",
    gate: "Loading the game",
  },
};

const CSS = `
@font-face { font-family: Uncial; src: url(/assets/fonts/UncialAntiqua-Regular.ttf); font-display: swap; }
@font-face { font-family: Almendra; src: url(/assets/fonts/Almendra-Regular.ttf); font-display: swap; }
@font-face { font-family: Fredoka; font-weight: 300 700; src: url(/assets/fonts/Fredoka.ttf); font-display: swap; }
.rg {
  position: fixed; inset: 0; z-index: 1000; display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: clamp(.8rem, 3vmin, 1.6rem); padding: 1.5rem; box-sizing: border-box; color: #fff1e0; text-align: center;
  background: radial-gradient(ellipse 60rem 40rem at 50% 40%, #2a1b55, #120d24 65%, #0c0919);
  font: 18px/1.5 Almendra, Georgia, serif; transition: opacity .7s ease; user-select: none;
}
.rg.gone { opacity: 0; pointer-events: none; }
.rg-sky {
  position: absolute; inset: 0; opacity: .6; pointer-events: none;
  background-image:
    radial-gradient(1.5px 1.5px at 8% 22%, #fff, transparent), radial-gradient(1px 1px at 28% 72%, #fff, transparent),
    radial-gradient(2px 2px at 62% 12%, #ffc94a, transparent), radial-gradient(1px 1px at 78% 62%, #fff, transparent),
    radial-gradient(1.5px 1.5px at 86% 28%, #fff, transparent), radial-gradient(2px 2px at 93% 82%, #b794ff, transparent),
    radial-gradient(1px 1px at 14% 88%, #fff, transparent), radial-gradient(1px 1px at 40% 90%, #b794ff, transparent);
}
.rg-gate { position: relative; width: min(72vmin, 26rem); aspect-ratio: 1; flex: none; }
.rg-gate svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }
.rg-horizon {
  position: absolute; inset: 15.75%; border-radius: 50%; overflow: hidden;
  background: radial-gradient(circle, #1c1536, #0c0919 70%);
  box-shadow: inset 0 0 40px #000;
}
.rg-horizon::before {
  content: ""; position: absolute; inset: -25%; opacity: 0;
  background: conic-gradient(from 0deg, #3a2a8a, #8b5cf6, #d9c8ff, #6d3cf0, #2a1b6e, #b794ff, #5b3ad0, #3a2a8a);
  filter: blur(10px) saturate(1.3);
}
.rg-horizon::after {
  content: ""; position: absolute; inset: 0; border-radius: 50%; opacity: 0;
  background: radial-gradient(circle, #ffffffcc 0, #d9c8ff88 25%, transparent 60%);
}
.rg-ripple {
  position: absolute; inset: 0; border-radius: 50%; opacity: 0; pointer-events: none;
  background: repeating-radial-gradient(circle, transparent 0 7%, #ffffff30 8%, transparent 10%);
  box-shadow: inset 0 0 30px 12px #120d24cc;
}
.rg.open .rg-ripple { opacity: 1; animation: rg-ripple 1.6s linear infinite; }
.rg-horizon img {
  position: absolute; left: 30%; top: 30%; width: 40%; height: 40%; image-rendering: pixelated; opacity: .55;
  filter: drop-shadow(0 0 18px #8b5cf6); animation: rg-float 4s ease-in-out infinite;
}
.rg.open .rg-horizon::before { opacity: 1; animation: rg-swirl 2.4s linear infinite, rg-in .5s ease-out both; }
.rg.open .rg-horizon::after { animation: rg-flash 1.1s ease-out both; }
.rg.open .rg-horizon { animation: rg-kawoosh .9s cubic-bezier(.2, 1.6, .4, 1) both; }
.rg-band { fill: none; stroke: #0c0919; stroke-width: 32; }
.rg-rune { fill: none; stroke: #5b4a96; stroke-width: 2.6; stroke-linecap: square; stroke-linejoin: miter; transition: stroke .3s; }
.rg-rune.lit { stroke: #ffc94a; filter: url(#rg-glow); }
.rg-chev-frame { fill: #3a404c; stroke: #0b0c10; stroke-width: 3; stroke-linejoin: round; }
.rg-chev-light { fill: #4a3a28; stroke: #0b0c10; stroke-width: 1.5; transition: fill .2s; }
.rg-chev.on .rg-chev-light { fill: #ffc94a; filter: url(#rg-glow); }
.rg-chev.on .rg-chev-frame { fill: #525a69; }
.rg-chev-move { transition: transform .12s; }
.rg-chev.engage .rg-chev-move { animation: rg-engage .3s ease-in-out; }
.rg.failed .rg-chev-light { fill: #b3261e; filter: none; }
.rg.failed .rg-rune.lit { stroke: #ff8a80; filter: none; }
.rg-title { margin: 0; font: clamp(1.8rem, 5vmin, 2.6rem)/1 Uncial, serif; color: #ffc94a; text-shadow: 4px 4px 0 #0b0c10; }
.rg-msg { margin: 0; min-height: 1.5em; font-size: clamp(1rem, 2.6vmin, 1.2rem); color: #e6dcf7; }
.rg-count { display: flex; align-items: center; gap: .9rem; font: 500 .9rem Fredoka, system-ui, sans-serif; color: #b3a8d6; letter-spacing: .04em; }
.rg-pips { display: flex; gap: 5px; }
.rg-pips i { width: 12px; height: 12px; border: 2px solid #0b0c10; border-radius: 3px; background: #2a2050; transition: background .2s, box-shadow .2s; }
.rg-pips i.on { background: #ffc94a; box-shadow: 0 0 8px #ffc94a88; }
.rg.failed .rg-pips i.on { background: #b3261e; box-shadow: none; }
.rg-error { margin: 0; max-width: 34rem; font: .95rem Fredoka, system-ui, sans-serif; color: #ff8a80; }
.rg button {
  min-height: 48px; padding: 0 1.4rem; border: 3px solid #0b0c10; border-radius: 10px; background: #ffc94a; color: #1a1206;
  font: 600 1.05rem Fredoka, system-ui, sans-serif; cursor: pointer; box-shadow: 0 5px 0 #0b0c10;
}
.rg button:hover { background: #ffd76e; }
.rg button:focus-visible { outline: 3px solid #ffc94a; outline-offset: 4px; }
@keyframes rg-engage { 40% { transform: translateY(7px); } 70% { transform: translateY(5px); } }
@keyframes rg-swirl { to { transform: rotate(360deg); } }
@keyframes rg-in { from { transform: scale(.2); } }
@keyframes rg-flash { 0% { opacity: 0; } 25% { opacity: 1; } 100% { opacity: .15; } }
@keyframes rg-kawoosh { 0% { transform: scale(.6); } 60% { transform: scale(1.08); } 100% { transform: scale(1); } }
@keyframes rg-ripple { from { transform: scale(1); } to { transform: scale(1.25); } }
@keyframes rg-float { 50% { transform: translateY(-6px); } }
@media (prefers-reduced-motion: reduce) {
  .rg *, .rg *::before, .rg *::after { animation: none !important; }
}
`;

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);

function svg(tag, attrs = {}, ...children) {
  const e = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  e.append(...children);
  return e;
}
function html(tag, props = {}, ...children) {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

/** The site's language: the one chosen on the site, else the browser's. */
function language() {
  let l = null;
  try { l = localStorage.getItem("octo.lang"); } catch {}
  return l === "fr" || l === "en" ? l : navigator.language?.startsWith("fr") ? "fr" : "en";
}

export function runeGate(parent = document.body, { lang = language() } = {}) {
  const t = TEXT[lang] ?? TEXT.en;
  if (!document.getElementById("rg-style")) document.head.append(html("style", { id: "rg-style", textContent: CSS }));

  // --- The ring ---
  const defs = svg("defs", {}, svg("filter", { id: "rg-glow", x: "-50%", y: "-50%", width: "200%", height: "200%" },
    svg("feGaussianBlur", { stdDeviation: "2.2", result: "b" }),
    svg("feMerge", {}, svg("feMergeNode", { in: "b" }), svg("feMergeNode", { in: "SourceGraphic" }))));
  const runes = GLYPHS.map((d, k) => {
    const a = k * STEP;
    return svg("path", { class: "rg-rune", d, transform: `rotate(${a}) translate(0 -162)` });
  });
  const ring = svg("g", {}, svg("circle", { class: "rg-band", r: 162 }), ...runes);
  const chevrons = Array.from({ length: CHEVRONS }, (_, i) => {
    const a = i * (360 / CHEVRONS); // 0 = the top chevron
    const g = svg("g", { class: "rg-chev", transform: `rotate(${a}) translate(0 -183)` },
      svg("g", { class: "rg-chev-move" },
        svg("polygon", { class: "rg-chev-frame", points: "-21,-13 21,-13 11,15 -11,15" }),
        svg("polygon", { class: "rg-chev-light", points: "-14,-8 -7,-8 0,3 7,-8 14,-8 0,12" })));
    return g;
  });
  const gateSvg = svg("svg", { viewBox: "-200 -200 400 400", "aria-hidden": "true" }, defs,
    svg("circle", { r: 194, fill: "#1c1536", stroke: "#0b0c10", "stroke-width": 6 }),
    svg("circle", { r: 186, fill: "none", stroke: "#2a2050", "stroke-width": 3 }),
    ring,
    svg("circle", { r: 178, fill: "none", stroke: "#0b0c10", "stroke-width": 3 }),
    svg("circle", { r: 146, fill: "none", stroke: "#0b0c10", "stroke-width": 5 }),
    svg("circle", { r: 141, fill: "none", stroke: "#3a2a6e", "stroke-width": 3 }),
    ...chevrons.slice(1), chevrons[0]);

  const pips = html("span", { className: "rg-pips" }, ...Array.from({ length: CHEVRONS }, () => html("i")));
  const msg = html("p", { className: "rg-msg", textContent: t.dial });
  const count = html("span", { textContent: t.none });
  const root = html("div", { className: "rg", role: "progressbar", ariaLabel: t.gate, ariaValueMin: 0, ariaValueMax: CHEVRONS, ariaValueNow: 0 },
    html("div", { className: "rg-sky" }),
    html("div", { className: "rg-gate" },
      gateSvg, html("div", { className: "rg-horizon" }, html("div", { className: "rg-ripple" }), html("img", { src: "/assets/icon.png", alt: "" }))),
    html("p", { className: "rg-title", textContent: "Octo Magic" }),
    msg,
    html("div", { className: "rg-count" }, pips, count));
  root.setAttribute("aria-label", t.gate);
  root.setAttribute("aria-valuemin", "0");
  root.setAttribute("aria-valuemax", String(CHEVRONS));
  parent.append(root);

  // --- Dialing: one chevron after the other, never ahead of `wanted`. ---
  let angle = 0; // the ring's rotation
  let locked = 0;
  let wanted = 0; // chevrons the loading allows
  let failed = false;
  let dialing = null;
  const order = [1, 2, 3, 4, 5, 6, 7, 8, 0]; // the top chevron locks last
  // Distinct runes to dial, the same each load.
  const address = [3, 17, 9, 21, 6, 14, 1, 11, 19];

  function spin(target, dir, ms) {
    // The way `dir`, at least a quarter turn, to put rune `target` under the top chevron.
    const goal = -target * STEP;
    let delta = (((goal - angle) % 360) + 360) % 360;
    if (dir < 0) delta -= 360;
    if (Math.abs(delta) < 90) delta += 360 * dir;
    const from = angle;
    if (reduced()) {
      angle = from + delta;
      ring.setAttribute("transform", `rotate(${angle})`);
      return Promise.resolve();
    }
    return new Promise((done) => {
      const t0 = performance.now();
      const frame = (now) => {
        const k = Math.min(1, (now - t0) / ms);
        angle = from + delta * ease(k);
        ring.setAttribute("transform", `rotate(${angle})`);
        if (k < 1) requestAnimationFrame(frame);
        else done();
      };
      requestAnimationFrame(frame);
    });
  }

  async function lockNext() {
    const n = locked; // 0-based
    msg.textContent = t.steps[n];
    const behind = wanted - locked;
    await spin(address[n], n % 2 ? -1 : 1, behind > 1 ? 320 : 650);
    if (failed) return;
    const top = chevrons[0];
    top.classList.remove("engage");
    void top.getBBox();
    top.classList.add("engage");
    await wait(reduced() ? 0 : behind > 1 ? 150 : 220);
    runes[address[n]].classList.add("lit");
    chevrons[order[n]].classList.add("on");
    pips.children[n].classList.add("on");
    locked = n + 1;
    count.textContent = t.locked(locked);
    root.setAttribute("aria-valuenow", String(locked));
    await wait(reduced() ? 0 : behind > 1 ? 40 : 120);
  }

  function dial() {
    dialing ??= (async () => {
      while (!failed && locked < wanted) await lockNext();
      dialing = null;
    })();
    return dialing;
  }

  return {
    element: root,
    /** The download, 0..1: chevrons 1 to 7. */
    progress(fraction) {
      const n = Math.max(0, Math.min(DOWNLOAD_CHEVRONS, Math.floor(fraction * DOWNLOAD_CHEVRONS + 1e-6)));
      if (n > wanted) {
        wanted = n;
        dial();
      }
    },
    /** The engine runs: the 8th chevron; then the 9th, the portal, and the gate goes. */
    async finish() {
      wanted = CHEVRONS;
      while (!failed && (dialing || locked < wanted)) await dial();
      if (failed) return;
      root.classList.add("open");
      await wait(reduced() ? 200 : 1300);
      root.classList.add("gone");
      await wait(750);
      root.remove();
    },
    /** Loading failed: red chevrons, the error and a retry button. */
    fail(message) {
      failed = true;
      root.classList.add("failed");
      msg.textContent = "";
      root.append(html("p", { className: "rg-error", textContent: String(message ?? "") }),
        html("button", { type: "button", textContent: t.retry, onclick: () => location.reload() }));
    },
  };
}
