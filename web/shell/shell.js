// fse shell pages: a mod's window as a web page over the game, with <engine-island> holes where the game's own GUI
// (a camera, slots, choose-elem buttons...) shows through. Include it first in the page's <head>:
//   <link rel="stylesheet" href="/shell/shell.css"><script src="/shell/shell.js"></script>
//
//   fse.send(data)                 to the mod: its shell.on_message(fn(player, name, data)) hears it, on the game thread
//   fse.on(fn(data))               from the mod: shell.send(player, name, data)
//   fse.onTheme(fn(theme))         the player's fse-std theme (also as CSS variables, below), now and on every change
//   fse.close() / fse.hide()       closes the shell (the mod hears on_close "page") / hides it
//   fse.keyboard(true | false)     take the keyboard from the game / give it back (text fields do this themselves)
//   fse.name, fse.theme, fse.gu    the shell's name, the theme, one game GUI unit in CSS px
//   <engine-island id="cam">       a hole: the mod's shell.island(player, name, "cam", build) frame sits exactly under it
//                                  (its padding box: a border drawn around it stays the page's)
//   data-fse-solid                 on elements: only these (their union, rounded by their border radius) are the shell;
//                                  everything else is see-through to the game (without any: the whole page)
//   data-fse-drag / data-fse-resize   pressing there moves / resizes the shell
// CSS variables: --fse-<token> for every theme colour (win, section, inset, deep, btn, btn_on, ok, slot, field, drag,
// title, caption, ink, ink_dim, btn_ink, btn_on_ink, ok_ink, field_ink), --fse-<token>-rgb ("r g b", for
// rgb(var(--fse-win-rgb) / 50%)), --fse-pad, --fse-gap, --fse-radius, --fse-font, --fse-gu; <html data-fse-theme=
// data-fse-shape= data-fse-light=>. Opened in a plain browser (no fse), the page still works: messages go nowhere.
(() => {
  "use strict";
  const init = window.__fseShellInit || { name: "", scale: 1, gu: 1, theme: null, standalone: true };
  const host = window.ipc && window.ipc.postMessage ? window.ipc : (window.chrome && window.chrome.webview) || null;
  const post = (m) => { if (host) host.postMessage(JSON.stringify(m)); };
  const handlers = [], themers = [];

  const fse = window.fse = {
    name: init.name, owner: init.owner, theme: init.theme, gu: init.gu || 1, standalone: !host,
    send(data) { post({ t: "msg", data }); },
    on(fn) { handlers.push(fn); },
    onTheme(fn) { themers.push(fn); if (fse.theme) fn(fse.theme); },
    close() { post({ t: "close" }); },
    hide() { post({ t: "set", visible: false }); },
    keyboard(web) { post({ t: "focus", web: !!web }); },
    log(text) { post({ t: "log", text: String(text) }); },
    relayout() { last = ""; },
  };

  // ---- theme -> CSS variables ----
  const RADIUS = { vanilla: 0, square: 0, soft: 4, round: 10 };
  function applyTheme(th) {
    if (!th) return;
    fse.theme = th;
    const root = document.documentElement, st = root.style;
    for (const [k, c] of Object.entries(th.colors || {})) {
      const [r, g, b] = c.slice(0, 3).map((x) => Math.round(x * 255));
      st.setProperty(`--fse-${k}`, `rgb(${r} ${g} ${b} / ${c[3] ?? 1})`);
      st.setProperty(`--fse-${k}-rgb`, `${r} ${g} ${b}`);
    }
    st.setProperty("--fse-pad", `${th.pad ?? 8}px`);
    st.setProperty("--fse-gap", `${th.gap ?? 8}px`);
    st.setProperty("--fse-radius", `${RADIUS[th.shape] ?? 4}px`);
    st.setProperty("--fse-font", th.mono ? '"Cascadia Mono", Consolas, monospace' : '"Titillium Web", "Segoe UI", sans-serif');
    root.dataset.fseTheme = th.name || "";
    root.dataset.fseShape = th.shape || "";
    root.dataset.fseLight = th.light ? "1" : "0";
    for (const fn of themers) try { fn(th); } catch (e) { console.error(e); }
  }
  function applyScale(gu) {
    fse.gu = gu || 1;
    document.documentElement.style.setProperty("--fse-gu", `${fse.gu}px`);
  }

  // native -> page: evaluate_script("window.__fseShell.receive({...})")
  window.__fseShell = {
    receive(env) {
      if (!env) return;
      if (env.t === "msg") for (const fn of handlers) try { fn(env.data); } catch (e) { console.error(e); }
      else if (env.t === "theme") applyTheme(env.theme);
      else if (env.t === "scale") { applyScale(env.gu); last = ""; }
    },
  };

  // ---- islands ----
  class EngineIsland extends HTMLElement {
    connectedCallback() { last = ""; }
    disconnectedCallback() { last = ""; }
  }
  if (!customElements.get("engine-island")) customElements.define("engine-island", EngineIsland);

  const clipping = (el) => {
    const s = getComputedStyle(el);
    return s.overflow !== "visible" || s.overflowX !== "visible" || s.overflowY !== "visible";
  };
  // an element's visible box (its padding box, cut by every ancestor that clips) in CSS px, or null
  function box(el) {
    if (!el.isConnected || el.offsetParent === null && getComputedStyle(el).position !== "fixed") return null;
    const s = getComputedStyle(el);
    if (s.visibility === "hidden" || +s.opacity === 0) return null;
    const r = el.getBoundingClientRect();
    let l = r.left + el.clientLeft, t = r.top + el.clientTop;
    let rr = l + el.clientWidth, b = t + el.clientHeight;
    for (let p = el.parentElement; p && p !== document.documentElement; p = p.parentElement) {
      if (!clipping(p)) continue;
      const q = p.getBoundingClientRect();
      l = Math.max(l, q.left + p.clientLeft); t = Math.max(t, q.top + p.clientTop);
      rr = Math.min(rr, q.left + p.clientLeft + p.clientWidth); b = Math.min(b, q.top + p.clientTop + p.clientHeight);
    }
    l = Math.max(l, 0); t = Math.max(t, 0); rr = Math.min(rr, innerWidth); b = Math.min(b, innerHeight);
    return rr > l && b > t ? [l, t, rr, b] : null;
  }
  const px = (b, dpr) => {
    const x = Math.round(b[0] * dpr), y = Math.round(b[1] * dpr);
    return [x, y, Math.round(b[2] * dpr) - x, Math.round(b[3] * dpr) - y];
  };

  let last = "";
  function measure() {
    const dpr = devicePixelRatio || 1;
    const islands = {};
    for (const el of document.querySelectorAll("engine-island[id]")) {
      const b = box(el);
      islands[el.id] = b ? px(b, dpr) : [0, 0, 0, 0];
    }
    let solid = null;
    const parts = document.querySelectorAll("[data-fse-solid]");
    if (parts.length) {
      solid = [];
      for (const el of parts) {
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0 || getComputedStyle(el).visibility === "hidden") continue;
        const radius = parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0;
        solid.push([...px([r.left, r.top, r.right, r.bottom], dpr), Math.round(radius * dpr)]);
      }
    }
    const text = JSON.stringify({ islands, solid });
    if (text !== last) {
      last = text;
      post({ t: "layout", islands, solid, dpr, w: innerWidth, h: innerHeight });
    }
  }
  // (every frame: a hole follows a CSS animation, a transition, a scroll, as it happens)
  const frame = () => { try { measure(); } catch (e) { console.error(e); } requestAnimationFrame(frame); };

  // ---- keyboard: the game keeps it unless a text field is focused ----
  const editable = (el) => !!el && el !== document.body &&
    (el.isContentEditable || el.tagName === "TEXTAREA" || el.tagName === "SELECT" ||
     (el.tagName === "INPUT" && !["button", "checkbox", "radio", "range", "color", "submit", "reset", "file", "image"].includes(el.type)));
  let web = false;
  const want = (w) => { if (w !== web) { web = w; fse.keyboard(w); } };
  addEventListener("pointerdown", (e) => { if (editable(e.target)) want(true); }, true);
  addEventListener("focusin", (e) => { if (editable(e.target)) want(true); });
  addEventListener("focusout", () => setTimeout(() => { if (!editable(document.activeElement)) want(false); }, 0));
  addEventListener("pointerup", () => setTimeout(() => {
    if (!editable(document.activeElement)) { web = true; want(false); }  // (always: a click must not keep the keyboard)
  }, 0), true);
  addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || e.defaultPrevented) return;
    if (editable(document.activeElement)) { document.activeElement.blur(); want(false); return; }
    post({ t: "esc" });
  });

  // ---- moving and resizing the shell from the page ----
  let drag = null;
  addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    const grip = e.target.closest && e.target.closest("[data-fse-drag],[data-fse-resize]");
    if (!grip || e.target.closest("button,input,select,textarea,a,engine-island,[data-fse-nodrag]")) return;
    drag = { mode: grip.hasAttribute("data-fse-resize") ? "resize" : "move", x: e.screenX, y: e.screenY, id: e.pointerId };
    grip.setPointerCapture(e.pointerId);
    post({ t: "drag", phase: "start", mode: drag.mode });
    e.preventDefault();
  });
  const dragMove = (e, phase) => {
    if (!drag || e.pointerId !== drag.id) return;
    const dpr = devicePixelRatio || 1;
    post({ t: "drag", phase, mode: drag.mode, dx: (e.screenX - drag.x) * dpr, dy: (e.screenY - drag.y) * dpr });
    if (phase === "end") drag = null;
  };
  addEventListener("pointermove", (e) => dragMove(e, "move"));
  addEventListener("pointerup", (e) => dragMove(e, "end"));
  addEventListener("pointercancel", (e) => dragMove(e, "end"));

  addEventListener("error", (e) => fse.log(`error: ${e.message} (${e.filename}:${e.lineno})`));
  addEventListener("unhandledrejection", (e) => fse.log(`unhandled: ${e.reason}`));

  applyScale(init.gu);
  if (init.theme) applyTheme(init.theme);
  const start = () => { post({ t: "hello" }); requestAnimationFrame(frame); };
  if (document.readyState === "loading") addEventListener("DOMContentLoaded", start); else start();
})();
