"use strict";

(() => {
  const $ = (selector, scope = document) => scope.querySelector(selector);
  const studio = $("#agent-studio");
  const root = $("#scene-root");
  const nav = $("#scene-nav");
  const caption = $("#scene-caption");
  const flowLabel = $("#flow-label");
  const flowDetail = $("#flow-detail");
  const controls = $("#demo-controls");
  const failureSelect = $("#failure");
  const menubarBadge = $("#menubar-tc");

  // SF Symbol stand-ins, drawn on a 24-point grid.
  const P = {
    chevL: '<path d="M15 5l-7 7 7 7"/>',
    chevD: '<path d="M6 9l6 6 6-6"/>',
    chevUD: '<path d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>',
    folder: '<path d="M3 7.5A1.5 1.5 0 0 1 4.5 6H9l2 2h8.5A1.5 1.5 0 0 1 21 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z"/>',
    move: '<path d="M3 7.5A1.5 1.5 0 0 1 4.5 6H9l2 2h8.5A1.5 1.5 0 0 1 21 9.5v8a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z"/><path d="M9 13.5h6M12.5 11l2.5 2.5-2.5 2.5"/>',
    hand: '<path d="M8 13V6.5a1.5 1.5 0 0 1 3 0V11m0-.5V5a1.5 1.5 0 0 1 3 0v6m0-.5V6.5a1.5 1.5 0 0 1 3 0V14c0 4-2.5 6.5-6 6.5-2.4 0-3.8-1.1-5-3l-2-3.3a1.4 1.4 0 0 1 2.3-1.6L8 14"/>',
    eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    bolt: '<path d="M13 3L5 13.5h6L10 21l8-10.5h-6z"/>',
    terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5"/>',
    doc: '<path d="M6.5 3h7L18 7.5V19a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M13.5 3v4.5H18M8 12h7M8 15.5h5"/>',
    docPlus: '<path d="M6.5 3h7L18 7.5V19a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M13.5 3v4.5H18M11.25 11v6M8.25 14h6"/>',
    pencil: '<path d="M4 20l1-4.5L15.5 5a2.1 2.1 0 0 1 3 3L8 18.5zM13.5 7l3 3"/>',
    trash: '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10 11v6M14 11v6"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    list: '<path d="M9.5 7h10M9.5 12h10M9.5 17h10M5 7h.01M5 12h.01M5 17h.01"/>',
    calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
    wand: '<path d="M4 20L15 9M13 7l4 4"/><path d="M18 3l.7 1.8 1.8.7-1.8.7L18 8l-.7-1.8-1.8-.7 1.8-.7z"/>',
    plug: '<path d="M9 3v5M15 3v5M6.5 8h11v3.5a5.5 5.5 0 0 1-11 0zM12 17v4"/>',
    paperplane: '<path d="M21 3L10 14M21 3l-6.5 18-4.5-7-7-4.5z"/>',
    warn: '<path d="M12 4l9 16H3z"/><path d="M12 10v4.5M12 17.3v.2"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    checkCircle: '<circle cx="12" cy="12" r="9"/><path d="M7.8 12.3l2.9 2.9 5.5-5.6"/>',
    xmark: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
    arrowUp: '<path d="M12 19V5M6 11l6-6 6 6"/>',
    stop: '<rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor" stroke="none"/>',
    wrench: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.2L3.5 17.3a1.8 1.8 0 0 0 2.6 2.6l5.8-5.8a4 4 0 0 0 5.2-5.4l-2.6 2.6-2.4-.4-.4-2.4z"/>',
    lines: '<path d="M7 9.5h10M7 14.5h10"/>',
    uturn: '<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
    open: '<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10"/>',
    compose: '<path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6"/><path d="M17.5 3.5a2.1 2.1 0 0 1 3 3L13 14l-4 1 1-4z"/>',
    clip: '<path d="M20 11.5l-7.8 7.8a5 5 0 0 1-7-7l8.3-8.3a3.3 3.3 0 0 1 4.7 4.7l-8.2 8.2a1.7 1.7 0 0 1-2.4-2.4l7.4-7.4"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/>',
    bubble: '<path d="M4 5.5h16v10H9l-4 3.5v-3.5H4z"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    sidebar: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M9.5 4.5v15"/>',
    project: '<path d="M3 10A1.5 1.5 0 0 1 4.5 8.5H8l1.8 1.8h7.7A1.5 1.5 0 0 1 19 11.8v7A1.5 1.5 0 0 1 17.5 20.3h-13A1.5 1.5 0 0 1 3 18.8z"/><path d="M6.5 8.5V6.8A1.5 1.5 0 0 1 8 5.3h3l1.8 1.8H19.5A1.5 1.5 0 0 1 21 8.6v7.2"/>',
    crop: '<path d="M6 3v13.5A1.5 1.5 0 0 0 7.5 18H21M3 6h13.5A1.5 1.5 0 0 1 18 7.5V21"/>',
    clipboard: '<rect x="5.5" y="4.5" width="13" height="16.5" rx="2"/><path d="M9 4.5V3.5h6v1M9 10h6M9 14h4"/>',
  };
  const icon = (name, cls = "") => `<svg class="i${cls ? ` ${cls}` : ""}" viewBox="0 0 24 24" aria-hidden="true">${P[name] || ""}</svg>`;
  const html = (markup) => {
    const template = document.createElement("template");
    template.innerHTML = markup.trim();
    return template.content.firstElementChild;
  };
  const esc = (value) => String(value).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

  // Every async flow carries the token it started under, so leaving a scene strands it harmlessly.
  let token = 0;
  const timers = new Set();
  const live = (t) => t === token;
  const wait = (ms, t) => new Promise((resolve) => {
    const id = setTimeout(() => { timers.delete(id); resolve(live(t)); }, ms);
    timers.add(id);
  });
  const every = (ms, fn) => { const id = setInterval(fn, ms); timers.add(id); return id; };

  const state = { scene: "palette", failure: "none", sidebarCollapsed: false, peekEnabled: true };
  let current = null;
  let pending = null;
  let modal = null;
  let menu = null;
  let activeWindow = null;
  let sidebarPeek = null;

  /* ---------- Shared building blocks ---------- */

  const AGENTS = {
    claude: { tile: "✳", cls: "claude", label: "Claude Code · Opus 5.5", short: "Claude Code" },
    codex: { tile: "◎", cls: "codex", label: "Codex · GPT-5.5", short: "Codex" },
    pi: { tile: "π", cls: "pi", label: "pi · DeepSeek V4", short: "pi" },
  };
  const MODES = {
    "只读": { icon: "eye", note: "只看不改，适合先摸清情况" },
    "询问": { icon: "hand", note: "改文件、运行命令前先问你" },
    "自动编辑": { icon: "bolt", note: "文件夹内直接改，命令仍会询问" },
  };
  const FOLDERS = [
    { name: "下载", path: "~/Downloads" },
    { name: "桌面", path: "~/Desktop" },
    { name: "tinycast", path: "~/code/github/tinycast" },
  ];
  // A project is a named set of folders; only the read-write ones are where an agent may change things.
  const PROJECTS = [
    { name: "周报", folders: [{ name: "文稿/周报", path: "~/Documents/周报", access: "读写" }, { name: "下载", path: "~/Downloads", access: "只读" }] },
    { name: "tinycast", folders: [{ name: "tinycast", path: "~/code/github/tinycast", access: "读写" }, { name: "pi", path: "~/code/github/pi", access: "只读" }] },
    { name: "发票整理", folders: [{ name: "下载", path: "~/Downloads", access: "读写" }, { name: "文稿/财务", path: "~/Documents/财务", access: "读写" }] },
  ];
  const projectByName = (name) => PROJECTS.find((p) => p.name === name);
  const projectSummary = (p) => p.folders.map((f) => `${f.name}（${f.access}）`).join("、");
  const agentTile = (key) => `<span class="agent-tile ${AGENTS[key].cls}">${AGENTS[key].tile}</span>`;

  function makeTranscript(list, scroller) {
    const nearBottom = () => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 140;
    const follow = () => scroller.scrollTo({ top: scroller.scrollHeight, behavior: "smooth" });
    const tx = {
      list,
      pinned: null,
      add(node) {
        const near = nearBottom();
        node.classList.add("appear");
        list.insertBefore(node, tx.pinned && tx.pinned.isConnected ? tx.pinned : null);
        if (near) requestAnimationFrame(follow);
        return node;
      },
      keepUp() { if (nearBottom()) follow(); },
    };
    return tx;
  }

  async function stream(tx, text, t, speed = 18) {
    const node = tx.add(html('<div class="msg-ai"></div>'));
    for (let i = 0; i < text.length; i += 2) {
      node.innerHTML = `${esc(text.slice(0, i))}<span class="caret"></span>`;
      if (i % 16 === 0) tx.keepUp();
      if (!(await wait(speed, t))) return node;
    }
    node.textContent = text;
    tx.keepUp();
    return node;
  }

  function working(tx) {
    const node = html('<div class="line"><span class="spinner"></span><span>工作中</span><span class="elapsed">0:00</span></div>');
    tx.add(node);
    tx.pinned = node;
    const started = Date.now();
    const id = every(500, () => {
      const s = Math.floor((Date.now() - started) / 1000);
      node.querySelector(".elapsed").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    });
    return {
      done() {
        clearInterval(id);
        timers.delete(id);
        if (tx.pinned === node) tx.pinned = null;
        node.remove();
      },
    };
  }

  const UNITS = {
    list: (n) => `查看了 ${n} 个文件夹`,
    search: (n) => `搜索了 ${n} 次`,
    read: (n) => `读取了 ${n} 处`,
    skill: (n) => `使用了 ${n} 个技能`,
    command: (n) => `运行了 ${n} 条命令`,
  };
  const summarize = (calls) => {
    const counts = new Map();
    for (const call of calls) counts.set(call.group, (counts.get(call.group) || 0) + 1);
    return [...counts].map(([group, n]) => UNITS[group](n)).join("，");
  };
  const callRow = (c) => `<div class="line done${c.detail ? " has-detail" : ""}">${icon(c.icon)}<span>${esc(c.verb)}</span><span class="target${c.mono ? " mono" : ""}">${esc(c.target)}</span></div>${c.detail ? `<div class="detail" hidden>${esc(c.detail)}</div>` : ""}`;

  function toolRun(tx) {
    const node = tx.add(html('<div class="run"></div>'));
    const calls = [];
    return {
      async call(c, t, ms = 650) {
        node.innerHTML = `<div class="line appear"><span class="spinner"></span><span>${esc(c.verb)}</span><span class="target${c.mono ? " mono" : ""}">${esc(c.target)}</span></div>`;
        tx.keepUp();
        calls.push(c);
        return wait(ms, t);
      },
      close() {
        if (calls.length === 1) {
          node.innerHTML = callRow(calls[0]);
        } else {
          node.innerHTML = `<button class="toggle-line" type="button">${icon("wrench")}<span>${esc(summarize(calls))}</span>${icon("chevD", "chev")}</button><div class="collapse"><div><div class="run-list">${calls.map(callRow).join("")}</div></div></div>`;
        }
        node.classList.remove("appear");
        void node.offsetWidth;
        node.classList.add("appear");
      },
    };
  }

  const line = (glyph, text, target = "", cls = "") =>
    html(`<div class="line ${cls}">${glyph}<span>${esc(text)}</span>${target ? `<span class="target">${esc(target)}</span>` : ""}</div>`);

  function notice(tx, { title, body, action }) {
    return new Promise((resolve) => {
      const node = tx.add(html(`<div class="notice">${icon("warn")}<div class="flex"><b>${esc(title)}</b><span>${esc(body)}</span></div>${action ? `<button class="mini-btn">${esc(action)}</button>` : ""}</div>`));
      const button = node.querySelector("button");
      if (button) button.addEventListener("click", () => { node.remove(); resolve(true); }, { once: true });
    });
  }

  function divider(tx, text) {
    tx.add(html(`<div class="divider-line">${esc(text)}</div>`));
  }

  function undoInPlace(changes, text, target, onRestore) {
    const undone = html(`<div class="line">${icon("uturn")}<span>${esc(text)}</span><span class="target">${esc(target)}</span><button class="mini-btn" data-restore>恢复</button></div>`);
    changes.replaceWith(undone);
    undone.classList.add("appear");
    undone.querySelector("[data-restore]").addEventListener("click", () => {
      undone.replaceWith(changes);
      changes.classList.remove("appear");
      void changes.offsetWidth;
      changes.classList.add("appear");
      onRestore();
    });
  }

  function makePlan(dock, steps, onResize) {
    let index = 0;
    const node = html(`<div class="plan glass"><button class="plan-head" type="button"><span class="spinner"></span><span class="count"></span><span class="now"></span>${icon("chevD", "chev")}</button><div class="collapse"><div><ol class="plan-list"></ol></div></div></div>`);
    node.classList.add("rise");
    dock.prepend(node);
    const draw = () => {
      node.querySelector(".count").textContent = `计划 ${Math.min(index + 1, steps.length)}/${steps.length}`;
      node.querySelector(".now").textContent = steps[Math.min(index, steps.length - 1)];
      node.querySelector(".plan-list").innerHTML = steps.map((s, i) => `<li class="${i < index ? "done" : i === index ? "now" : ""}">${i < index ? icon("check") : '<span class="ring"></span>'}<span>${esc(s)}</span></li>`).join("");
      onResize();
    };
    node.querySelector(".plan-head").addEventListener("click", () => { node.classList.toggle("open"); setTimeout(onResize, 200); });
    draw();
    return {
      next() { index += 1; draw(); },
      done() { node.classList.add("sink"); setTimeout(() => { node.remove(); onResize(); }, 130); },
    };
  }

  async function confirmAutoEdit(agentKey, folder) {
    return confirmDialog({
      glyph: "bolt",
      title: `让 ${AGENTS[agentKey].short} 直接改文件？`,
      message: `在「${folder || "当前文件夹"}」里改文件不再逐个询问；运行命令、删除和外部写操作仍会先问你。随时可以切回「询问」。`,
      confirm: "允许自动编辑",
    });
  }

  /* ---------- Approval ---------- */

  function approvalBody(spec) {
    let body = "";
    if (spec.code) body += `<div class="code">${spec.code.map((l) => `<div class="${l.cls || ""}">${esc(l.text)}</div>`).join("")}</div>`;
    if (spec.fields) body += `<dl class="ap-fields">${spec.fields.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join("")}</dl>`;
    if (spec.note) body += `<div class="ap-note">${icon("warn")}<span>${esc(spec.note)}</span></div>`;
    return body;
  }

  function approvalCard(spec) {
    const buttons = [
      '<button class="mbtn cancel" data-act="deny" data-tip="⎋">拒绝</button>',
      spec.session === false ? "" : '<button class="mbtn standard" data-act="session" data-tip="⌥ ↵">本次对话都允许</button>',
      spec.danger
        ? `<button class="mbtn destructive" data-act="allow">${esc(spec.allow || "允许")}</button>`
        : `<button class="mbtn primary" data-act="allow" data-tip="↵">${esc(spec.allow || "允许")}</button>`,
    ].join("");
    return html(`<div class="approval rise" role="alertdialog" aria-label="${esc(spec.title)}">
      <div class="ap-head"><span class="ap-glyph${spec.danger ? " danger" : ""}">${icon(spec.icon)}</span><div class="ap-titles"><b>${esc(spec.title)}</b><span>${esc(spec.sub)}</span></div>${spec.count ? `<span class="ap-count">${esc(spec.count)}</span>` : ""}</div>
      ${approvalBody(spec)}<div class="ap-actions">${buttons}</div></div>`);
  }

  function paletteApproval(spec) {
    const files = spec.files ? `<div class="files">${spec.files.map((f) => `<span>${esc(f)}</span>`).join("")}</div>` : "";
    const code = spec.code ? `<div class="code" style="margin-left:36px">${spec.code.map((l) => `<div>${esc(l.text)}</div>`).join("")}</div>` : "";
    return html(`<div class="pal-approval"><div class="ap-head"><span class="ap-glyph${spec.danger ? " danger" : ""}">${icon(spec.icon)}</span><div class="ap-titles"><b>${esc(spec.title)}</b><span>${esc(spec.sub)}</span></div></div>${files}${code}</div>`);
  }

  function ask(spec) {
    return new Promise((resolve) => { pending = { spec, resolve }; });
  }

  function decide(choice, text = "") {
    if (!pending) return;
    if (choice === "session" && pending.spec.session === false) return;
    const { resolve } = pending;
    pending = null;
    closeMenu();
    resolve({ choice, text });
  }

  /* ---------- Popover menu ---------- */

  function closeMenu() {
    if (!menu) return false;
    menu.node.remove();
    document.removeEventListener("mousedown", menu.outside, true);
    menu = null;
    return true;
  }

  function openMenu(anchor, items, { placement = "above-right", wide = false } = {}) {
    if (menu && menu.anchor === anchor) { closeMenu(); return; }
    closeMenu();
    const node = html(`<div class="popover${wide ? " wide" : ""}" role="menu"></div>`);
    for (const item of items) {
      if (item.sep) { node.appendChild(html('<div class="menu-sep"></div>')); continue; }
      if (item.head) { node.appendChild(html(`<div class="menu-head">${esc(item.head)}</div>`)); continue; }
      if (item.note) { node.appendChild(html(`<div class="menu-note">${esc(item.note)}</div>`)); continue; }
      const trail = item.check ? icon("check", "check") : (item.trail || []).map((k) => `<span>${esc(k)}</span>`).join("");
      const row = html(`<button class="menu-row${item.destructive ? " destructive" : ""}" role="menuitem"><span class="slot">${item.icon ? icon(item.icon) : item.tile || ""}</span><span>${esc(item.label)}</span><span class="trail">${trail}</span></button>`);
      row.addEventListener("click", () => { closeMenu(); if (item.act) item.act(); });
      node.appendChild(row);
    }
    const base = root.getBoundingClientRect();
    const r = anchor.getBoundingClientRect();
    const [vertical, horizontal] = placement.split("-");
    if (vertical === "above") node.style.bottom = `${base.bottom - r.top + 8}px`;
    else node.style.top = `${r.bottom - base.top + 6}px`;
    if (horizontal === "right") node.style.right = `${base.right - r.right}px`;
    else node.style.left = `${r.left - base.left}px`;
    node.style.transformOrigin = `${vertical === "above" ? "bottom" : "top"} ${horizontal}`;
    root.appendChild(node);
    const outside = (event) => { if (!node.contains(event.target) && !anchor.contains(event.target)) closeMenu(); };
    document.addEventListener("mousedown", outside, true);
    menu = { node, anchor, outside };
  }

  const modeMenu = (selected, onPick) => [
    { head: "模式" },
    ...Object.entries(MODES).map(([name, m]) => ({ icon: m.icon, label: name, check: name === selected, act: () => onPick(name) })),
    { note: "只读：只看不改 · 询问：动手前先问你 · 自动编辑：文件夹内直接改，命令仍会询问" },
  ];
  const agentMenu = (selected, onPick) => [
    { head: "Agent" },
    ...Object.entries(AGENTS).map(([key, a]) => ({ tile: agentTile(key), label: a.label, check: key === selected, act: () => onPick(key) })),
    { sep: true },
    { head: "对话模型" },
    { icon: "bubble", label: "Apple Intelligence", act: () => flash("（原型）选普通对话模型时，文件夹和模式控件会隐藏：它们不能在本机动手") },
    { icon: "bubble", label: "DeepSeek API · V4 Flash", act: () => flash("（原型）选普通对话模型时，文件夹和模式控件会隐藏：它们不能在本机动手") },
  ];

  /* ---------- HUD and dialog ---------- */

  function hud({ glyph, text, sub = "", button = null, dwell = 2400 }) {
    const node = html(`<div class="hud${button ? "" : " plain"}" role="status">${glyph}<span>${esc(text)}</span>${sub ? `<span class="sub">${esc(sub)}</span>` : ""}${button ? `<button class="hud-btn">${esc(button.label)}</button>` : ""}</div>`);
    root.appendChild(node);
    const dismiss = () => {
      if (!node.isConnected) return;
      node.classList.add("out");
      setTimeout(() => node.remove(), 130);
    };
    if (button) node.querySelector(".hud-btn").addEventListener("click", () => { dismiss(); button.act(); });
    else setTimeout(dismiss, dwell);
    return { dismiss };
  }

  function confirmDialog({ glyph, title, message, cancel = "取消", confirm, destructive = false }) {
    return new Promise((resolve) => {
      const layer = html(`<div class="scrim-layer"><div class="dialog" role="dialog" aria-label="${esc(title)}"><span class="sym">${icon(glyph)}</span><div><h3>${esc(title)}</h3><p>${esc(message)}</p></div><div class="ap-actions"><button class="mbtn cancel" data-tip="⎋">${esc(cancel)}</button><button class="mbtn ${destructive ? "destructive" : "standard"}" data-tip="↵">${esc(confirm)}</button></div></div></div>`);
      root.appendChild(layer);
      const finish = (value) => { modal = null; layer.remove(); resolve(value); };
      const [cancelButton, confirmButton] = layer.querySelectorAll(".mbtn");
      cancelButton.addEventListener("click", () => finish(false));
      confirmButton.addEventListener("click", () => finish(true));
      modal = { finish };
    });
  }

  let flashTimer = 0;
  function flash(text) {
    caption.textContent = text;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => { if (current) caption.textContent = current.caption; }, 3200);
  }

  /* ---------- Palette (scenes 01 and 05) ---------- */

  const MOVE_FILES = ["截屏 2026-10-12 09.41.png", "截屏 2026-10-13 15.02.png", "截屏 2026-10-14 11.27.png", "还有 6 个"];
  const MOVE_SPEC = { icon: "move", title: "移动 9 个文件", sub: "到「截图/2026-10」· Claude Code 请求确认", files: MOVE_FILES };
  const MKDIR_SPEC = { icon: "terminal", title: "运行命令", sub: "在「下载」中 · Claude Code 请求确认", code: [{ text: 'mkdir -p "截图/2026-10" && mv 截屏\\ 2026-10-1*.png "截图/2026-10/"' }] };

  function paletteShell({ folder = "下载", mode = "询问", warn = false } = {}) {
    return html(`<div class="palette" id="pal">
      <div class="pal-scroll" id="pal-scroll"><div class="transcript" id="pal-tx"></div></div>
      <div class="pal-header">
        <button class="pal-lead" aria-label="返回">${icon("chevL")}</button>
        <input class="pal-input" id="pal-input" placeholder="让 Claude Code 在「下载」里做点什么…" autocomplete="off" spellcheck="false">
        <button class="scope${warn ? " warn" : ""}" id="pal-scope">${icon(warn ? "warn" : "folder")}<span id="scope-folder">${esc(folder)}</span><span class="sep">·</span>${icon(MODES[mode].icon)}<span id="scope-mode">${esc(mode)}</span></button>
      </div>
      <div class="pal-footer">
        <button class="menu-circle glass" aria-label="菜单">${icon("lines")}</button>
        <div class="capsule glass">
          <button class="pill primary" id="pal-primary"><span class="label" id="pal-primary-label">发送</span><kbd>↵</kbd></button>
          <button class="pill secondary" id="pal-actions">操作 <kbd>⌘</kbd><kbd>K</kbd></button>
        </div>
      </div>
    </div>`);
  }

  function makePalette(scene, t, { autoHideAfterDone = false } = {}) {
    const failure = state.failure;
    const node = paletteShell({ warn: failure === "folder" });
    root.appendChild(node);
    const tx = makeTranscript($("#pal-tx"), $("#pal-scroll"));
    const input = $("#pal-input");
    const primaryLabel = $("#pal-primary-label");
    const ctx = { t, tx, input, node, folder: "下载", project: null, mode: "询问", phase: "idle", folderFixed: failure !== "folder", sessionAllowed: false, changes: null, waitingHud: null, pendingTitle: "" };
    const placeholderIdle = () => {
      const place = ctx.project || ctx.folder;
      return place ? `让 Claude Code 在「${place}」里做点什么…` : "让 Claude Code 做点什么…";
    };

    const setPrimary = (label) => {
      primaryLabel.style.opacity = "0";
      setTimeout(() => { primaryLabel.textContent = label; primaryLabel.style.opacity = "1"; }, 90);
    };
    ctx.setPhase = (phase) => {
      ctx.phase = phase;
      setPrimary({ idle: "发送", busy: "停止", pending: "允许" }[phase]);
      input.placeholder = { idle: placeholderIdle(), busy: "agent 正在工作…", pending: "↵ 允许，或输入其他指示…" }[phase];
    };
    ctx.hide = () => {
      node.classList.add("hidden");
      if (ctx.phase === "pending" && !ctx.waitingHud) {
        menubarBadge.classList.add("pending");
        ctx.waitingHud = hud({ glyph: icon("hand"), text: "Claude Code 等待确认", sub: `· ${ctx.pendingTitle}`, button: { label: "查看", act: () => ctx.show() } });
      }
    };
    ctx.show = () => {
      if (ctx.waitingHud) { ctx.waitingHud.dismiss(); ctx.waitingHud = null; }
      menubarBadge.classList.remove("pending");
      node.classList.remove("hidden");
      input.focus();
    };

    const scopeButton = $("#pal-scope");
    const refreshScope = () => {
      scopeButton.classList.toggle("warn", !ctx.folderFixed);
      const place = ctx.folderFixed ? placeLabel(ctx.project, ctx.folder) : `${icon("warn")}<span>${esc(ctx.folder)}</span>`;
      scopeButton.innerHTML = `${place}<span class="sep">·</span>${icon(MODES[ctx.mode].icon)}<span>${esc(ctx.mode)}</span>`;
    };
    const pickPlace = ({ project = null, folder = null }) => {
      ctx.project = project;
      ctx.folder = folder;
      ctx.folderFixed = true;
      refreshScope();
      if (ctx.phase === "idle") input.placeholder = placeholderIdle();
    };
    scopeButton.addEventListener("click", () => openMenu(scopeButton, [
      ...placeMenu(ctx.project, ctx.folder, pickPlace, async () => {
        const created = await newProjectDialog();
        if (created && node.isConnected) pickPlace({ project: created.name });
      }),
      { sep: true },
      ...modeMenu(ctx.mode, async (name) => {
        if (name === "自动编辑" && ctx.mode !== name && !(await confirmAutoEdit("claude", ctx.folder))) return;
        ctx.mode = name;
        refreshScope();
      }),
    ], { placement: "below-right", wide: true }));

    ctx.actionItems = () => {
      if (ctx.phase === "pending") {
        return [
          { icon: "check", label: "允许", trail: ["↵"], act: () => decide("allow") },
          { icon: "checkCircle", label: "本次对话都允许", trail: ["⌥", "↵"], act: () => decide("session") },
          { icon: "xmark", label: "拒绝", act: () => decide("deny") },
          { sep: true },
          { icon: "bubble", label: "在 AI Chat 中继续", trail: ["⌘", "J"], act: () => flash("（原型）对话和这张卡片一起转到 AI Chat 窗口") },
        ];
      }
      const items = [];
      if (ctx.phase === "busy") items.push({ icon: "stop", label: "停止", trail: ["⌘", "."], act: () => flash("（原型）停止当前任务；已完成的改动保留，可撤销") });
      if (ctx.changes) items.push({ icon: "uturn", label: "撤销这些改动", trail: ["⌘", "Z"], act: () => ctx.undo() });
      items.push({ icon: "bubble", label: "在 AI Chat 中继续", trail: ["⌘", "J"], act: () => flash("（原型）对话转到 AI Chat 窗口，带着文件夹和模式") });
      items.push({ icon: "compose", label: "新聊天", trail: ["⌘", "N"], act: () => enterScene(scene.id) });
      items.push({ sep: true });
      items.push({ icon: "clock", label: "聊天记录", trail: ["⌘", "Y"], act: () => flash("（原型）打开聊天记录") });
      return items;
    };
    $("#pal-actions").addEventListener("click", (e) => openMenu(e.currentTarget, ctx.actionItems(), { wide: true }));
    $("#pal-primary").addEventListener("click", () => ctx.primary());

    ctx.primary = () => {
      if (ctx.phase === "pending") return decide("allow");
      if (ctx.phase === "busy") return flash("（原型）主操作此时是「停止」");
      return ctx.send();
    };

    ctx.send = async () => {
      const text = input.value.trim();
      if (!text || ctx.phase !== "idle") return;
      input.value = "";
      tx.add(html(`<div class="msg-user">${esc(text)}</div>`));
      ctx.setPhase("busy");
      await ctx.run();
    };

    ctx.askHere = async (spec) => {
      const card = tx.add(paletteApproval(spec));
      ctx.pendingTitle = spec.title;
      ctx.setPhase("pending");
      if (node.classList.contains("hidden")) ctx.hide();
      const decision = await ask(spec);
      if (!live(t)) return decision;
      ctx.setPhase("busy");
      ctx.card = card;
      return decision;
    };

    const resolveCard = (glyph, text, target, cls = "") => {
      const replacement = line(glyph, text, target, cls);
      ctx.card.replaceWith(replacement);
      replacement.classList.add("appear");
      ctx.card = replacement;
      return replacement;
    };

    // Undo is itself undoable, so it needs no confirmation.
    ctx.undo = () => {
      if (!ctx.changes) return;
      const moved = ctx.changes;
      ctx.changes = null;
      undoInPlace(moved, "已撤销 9 处改动", "9 张截图已移回「下载」", () => { ctx.changes = moved; });
    };

    const showMoved = () => {
      const node = html(`<div class="changes"><button class="toggle-line" type="button">${icon("move")}<span>移动了 9 个文件</span><span class="t3">到「截图/2026-10」</span>${icon("chevD", "chev")}</button><div class="collapse"><div><div class="run-list">${MOVE_FILES.slice(0, 3).map((f) => `<div class="file-row"><span class="file-ic png"></span><span class="fname">${esc(f)}</span><span class="stat">→ 截图/2026-10</span><span class="row-actions"><button class="mini-btn">在访达中显示</button></span></div>`).join("")}<div class="file-row"><span class="stat">还有 6 个</span></div><button class="mini-btn undo" data-undo>${icon("uturn")} 撤销这些改动</button></div></div></div></div>`);
      ctx.card.replaceWith(node);
      node.classList.add("appear");
      node.querySelector("[data-undo]").addEventListener("click", () => ctx.undo());
      ctx.changes = node;
      return node;
    };

    ctx.run = async () => {
      let w = working(tx);
      if (!(await wait(550, t))) return;
      if (failure === "login") {
        w.done();
        await notice(tx, { title: "Claude Code 未登录", body: "在终端运行 claude 完成登录，然后重试。", action: "重试" });
        if (!live(t)) return;
        w = working(tx);
        if (!(await wait(400, t))) return;
      }
      if (!ctx.folderFixed) {
        w.done();
        await notice(tx, { title: "无法读取「下载」", body: "到 系统设置 › 隐私与安全性 › 完全磁盘访问权限 打开 Tinycast，或换一个文件夹。", action: "重新授权" });
        if (!live(t)) return;
        ctx.folderFixed = true;
        refreshScope();
        w = working(tx);
        if (!(await wait(400, t))) return;
      }
      const run = toolRun(tx);
      if (!(await run.call({ group: "list", icon: "folder", verb: "查看", target: "下载 · 86 项" }, t))) return;
      if (!(await run.call({ group: "search", icon: "search", verb: "筛选", target: "上周的截图 · 9 个" }, t))) return;
      run.close();
      await stream(tx, "找到 9 张上周的截图，准备移到「截图/2026-10」。", t);
      if (!live(t)) return;
      w.done();
      const decision = await ctx.askHere(MOVE_SPEC);
      if (!live(t)) return;
      if (decision.choice === "deny" || decision.choice === "redirect") {
        resolveCard(icon("xmark"), "已拒绝", "移动 9 个文件", "t3");
        if (decision.choice === "redirect") tx.add(html(`<div class="msg-user">${esc(decision.text)}</div>`));
        w = working(tx);
        if (!(await wait(600, t))) return;
        w.done();
        await stream(tx, decision.choice === "redirect"
          ? "明白，先不动文件。这是清单：\n1. 截屏 2026-10-12 09.41.png\n2. 截屏 2026-10-13 15.02.png\n3. 截屏 2026-10-14 11.27.png\n……共 9 个。"
          : "好的，没有移动任何文件。要不要我先列出清单给你看？", t);
        if (live(t)) ctx.setPhase("idle");
        return;
      }
      if (decision.choice === "session") ctx.sessionAllowed = true;
      resolveCard('<span class="spinner"></span>', "正在移动", "9 个文件");
      if (!(await wait(800, t))) return;
      if (failure === "cmdfail") {
        resolveCard(icon("warn"), "移动失败", "截图/2026-10：目标文件夹不存在", "failed");
        await stream(tx, "目标文件夹还不存在，我先创建它再移动。", t);
        if (!live(t)) return;
        const retry = await ctx.askHere(MKDIR_SPEC);
        if (!live(t)) return;
        if (retry.choice !== "allow" && retry.choice !== "session") {
          resolveCard(icon("xmark"), "已拒绝", "运行命令", "t3");
          ctx.setPhase("idle");
          return;
        }
        resolveCard('<span class="spinner"></span>', "正在运行", "mkdir && mv");
        if (!(await wait(700, t))) return;
      }
      showMoved();
      if (ctx.sessionAllowed) tx.add(line("", "本次对话内，移动和改名不再询问", "", "t3"));
      await stream(tx, "完成，9 张截图已移到「截图/2026-10」。", t);
      if (!live(t)) return;
      ctx.setPhase("idle");
      if (failure === "switch") {
        if (!(await wait(900, t))) return;
        divider(tx, "已切换到 Codex · GPT-5.5 — 新会话，前文以摘要带入");
        input.placeholder = "让 Codex 在「下载」里做点什么…";
      }
      if (autoHideAfterDone) {
        if (!(await wait(900, t))) return;
        ctx.hide();
        if (!(await wait(1100, t))) return;
        hud({ glyph: icon("checkCircle", "ok"), text: "完成", sub: "· 移动了 9 个文件" });
      }
    };

    ctx.onKey = (e) => {
      if (e.metaKey && e.key.toLowerCase() === "k") {
        openMenu($("#pal-actions"), ctx.actionItems(), { wide: true });
        return true;
      }
      // In the palette ⎋ keeps its meaning: hide. A pending card waits and becomes a HUD.
      if (e.key === "Escape") {
        if (node.classList.contains("hidden")) return true;
        ctx.hide();
        if (ctx.phase === "idle") setTimeout(() => { if (live(t)) ctx.show(); }, 1200);
        return true;
      }
      if (e.key === "Enter" && !e.altKey && !pending && ctx.phase === "idle") {
        ctx.send();
        return true;
      }
      return false;
    };

    input.value = "把下载里上周的截图移到「截图/2026-10」";
    input.focus();
    return ctx;
  }

  /* ---------- AI Chat window (scenes 02–04, 06) ---------- */

  const statusMarkup = (status) => (status === "pending" ? '<span class="dot" title="等待确认"></span>' : status === "running" ? '<span class="spinner"></span>' : "");
  const sideRow = (r) => `<button class="side-row${r.selected ? " selected" : ""}" data-chat="${esc(r.id || "")}"><span class="title">${esc(r.title)}</span><span class="status">${statusMarkup(r.status)}</span></button>`;
  const projectGroup = (g) => `<div class="proj${g.project.open ? " open" : ""}" data-project="${esc(g.project.name)}">
      <div class="proj-head" role="button" tabindex="0" title="${esc(projectSummary(g.project))}">${icon("chevD", "chev")}${icon("project")}<span class="name">${esc(g.project.name)}</span><span class="count">${g.project.folders.length} 个文件夹</span><span class="proj-dot"></span><button class="proj-add" type="button" aria-label="在这个项目里新建对话">${icon("plus")}</button></div>
      <div class="collapse"><div>${g.rows.map(sideRow).join("")}</div></div></div>`;
  function sidebar(groups) {
    return groups.map((g) => (g.project ? projectGroup(g) : `<div class="side-group">${esc(g.group)}</div>${g.rows.map(sideRow).join("")}`)).join("");
  }

  function chatGroups(selected, statuses = {}) {
    return [
      { project: { ...projectByName("周报"), open: true }, rows: [{ id: "report", title: "写第 42 周周报" }, { id: "w41", title: "第 41 周周报" }] },
      { project: { ...projectByName("tinycast"), open: true }, rows: [{ id: "proto", title: "Agent 模式原型" }, { id: "export", title: "修复截图导出" }] },
      { project: { ...projectByName("发票整理"), open: selected === "invoice" }, rows: [{ id: "invoice", title: "发票按月份重命名" }] },
      { group: "其他", rows: [{ id: "shots", title: "整理下载里的截图" }, { id: "crash", title: "解释这段崩溃日志" }] },
    ].map((g) => ({ ...g, rows: g.rows.map((r) => ({ ...r, selected: r.id === selected, status: statuses[r.id] })) }));
  }

  const placeMenu = (project, folder, onPick, onNewProject) => [
    { head: "项目" },
    ...PROJECTS.map((p) => ({ icon: "project", label: p.name, trail: [`${p.folders.length} 个文件夹`], check: project === p.name, act: () => onPick({ project: p.name }) })),
    { icon: "plus", label: "新建项目…", act: onNewProject },
    { sep: true },
    { head: "单个文件夹" },
    ...FOLDERS.map((f) => ({ icon: "folder", label: f.name, check: !project && folder === f.name, act: () => onPick({ folder: f.name }) })),
    { icon: "folder", label: "访达当前窗口 · 项目资料", act: () => onPick({ folder: "项目资料" }) },
    { icon: "xmark", label: "不使用文件夹", check: !project && !folder, act: () => onPick({}) },
  ];
  const placeLabel = (project, folder) => (project
    ? `${icon("project")}<span>${esc(project)}</span>`
    : `${icon("folder", folder ? "" : "dim")}<span>${esc(folder || "无文件夹")}</span>`);

  function newProjectDialog() {
    const folders = [
      { name: "tinycast", path: "~/code/github/tinycast", access: "读写" },
      { name: "下载", path: "~/Downloads", access: "只读" },
    ];
    return new Promise((resolve) => {
      const layer = html(`<div class="scrim-layer"><div class="dialog project-dialog" role="dialog" aria-label="新建项目">
        <div><h3>新建项目</h3><p>项目是一组文件夹和它们的默认设置。agent 在项目里只能改「读写」的文件夹；第一个是它的工作目录。</p></div>
        <label class="pd-field"><span class="pd-label">名称</span><input class="pd-input" id="pd-name" value="Agent 模式" spellcheck="false"></label>
        <div class="pd-field"><span class="pd-label">文件夹</span><div class="pd-folders" id="pd-folders"></div>
          <div class="pd-row"><button class="mini-btn" id="pd-add" type="button">${icon("plus")} 添加文件夹…</button></div>
          <span class="pd-hint">也可以从访达把文件夹拖进来。加入「桌面」「文稿」「下载」时，macOS 会在这一步问一次权限，而不是在任务进行到一半时。</span></div>
        <div class="pd-row"><span class="pd-label">默认</span><span class="popup">${agentTile("claude")} Claude Code ${icon("chevUD")}</span><span class="popup">${icon("hand")} 询问 ${icon("chevUD")}</span></div>
        <div class="ap-actions"><button class="mbtn cancel" data-tip="⎋">取消</button><button class="mbtn primary" data-tip="↵">创建</button></div>
      </div></div>`);
      root.appendChild(layer);
      const list = layer.querySelector("#pd-folders");
      const draw = () => {
        list.innerHTML = folders.map((f, i) => `<div class="pd-folder">${icon("folder")}<div class="meta"><b>${esc(f.name)}</b><span>${esc(f.path)}</span></div>${i === 0 ? '<span class="tag">工作目录</span>' : ""}<span class="seg" data-i="${i}"><button class="${f.access === "读写" ? "on" : ""}" data-access="读写">读写</button><button class="${f.access === "只读" ? "on" : ""}" data-access="只读">只读</button></span><button class="mini-btn" data-remove="${i}" aria-label="移除">${icon("xmark")}</button></div>`).join("");
      };
      list.addEventListener("click", (e) => {
        const access = e.target.closest("[data-access]");
        if (access) folders[Number(access.parentElement.dataset.i)].access = access.dataset.access;
        const remove = e.target.closest("[data-remove]");
        if (remove && folders.length > 1) folders.splice(Number(remove.dataset.remove), 1);
        draw();
      });
      layer.querySelector("#pd-add").addEventListener("click", () => {
        if (!folders.some((f) => f.name === "桌面")) folders.push({ name: "桌面", path: "~/Desktop", access: "读写" });
        draw();
      });
      draw();
      const finish = (ok) => {
        modal = null;
        layer.remove();
        if (!ok) return resolve(null);
        const project = { name: layer.querySelector("#pd-name").value.trim() || "新项目", folders: folders.map((f) => ({ ...f })) };
        PROJECTS.unshift(project);
        resolve(project);
      };
      const [cancel, create] = layer.querySelectorAll(".ap-actions .mbtn");
      cancel.addEventListener("click", () => finish(false));
      create.addEventListener("click", () => finish(true));
      modal = { finish };
      layer.querySelector("#pd-name").select();
    });
  }

  function windowShell({ title, sub = "", groups, placeholder, agent = "claude", folder = null, project = null, mode = "询问" }) {
    const node = html(`<div class="win${state.sidebarCollapsed ? " collapsed" : ""}">
      <div class="win-traffic" aria-hidden="true"><i></i><i></i><i></i></div>
      <button class="tb-btn win-sidebar-btn" type="button" aria-label="显示或隐藏侧边栏" title="显示或隐藏侧边栏  ⌘B">${icon("sidebar")}<span class="badge"></span></button>
      <div class="edge-zone" aria-hidden="true"></div>
      <aside class="win-side"><div class="side-search">${icon("search")}<span>搜索</span></div>${sidebar(groups)}</aside>
      <section class="win-main">
        <div class="win-toolbar"><span class="title">${esc(title)}</span><span class="sub">${esc(sub)}</span><span class="flex"></span><button class="tb-btn" aria-label="新聊天">${icon("compose")}</button></div>
        <div class="win-scroll" id="win-scroll"><div class="column transcript" id="win-tx"></div></div>
        <div class="composer-wrap column">
          <div class="dock" id="win-dock"></div>
          <div class="composer glass">
            <div class="staged" id="win-staged"></div>
            <textarea class="composer-input" id="win-input" rows="1" placeholder="${esc(placeholder)}"></textarea>
            <div class="composer-row">
              <button class="cc" id="cc-plus" aria-label="添加">${icon("plus")}</button>
              <button class="cc" id="cc-folder"></button>
              <button class="cc" id="cc-mode"></button>
              <span class="flex"></span>
              <button class="cc" id="cc-agent"></button>
              <button class="cc" id="cc-effort"><span>高</span>${icon("chevD", "chev")}</button>
              <button class="cc" aria-label="听写">${icon("mic")}</button>
              <button class="send" id="cc-send" aria-label="发送">${icon("arrowUp")}</button>
            </div>
          </div>
        </div>
      </section>
    </div>`);
    root.appendChild(node);
    const w = {
      node,
      tx: makeTranscript($("#win-tx"), $("#win-scroll")),
      input: $("#win-input"),
      dock: $("#win-dock"),
      agent, folder, project, mode,
      staged: [],
    };
    const stagedRow = $("#win-staged");
    const drawStaged = () => {
      stagedRow.innerHTML = w.staged.map((name, i) => `<span class="att"><span class="thumb"></span><span>${esc(name)}</span><button type="button" data-unstage="${i}" aria-label="移除">${icon("xmark")}</button></span>`).join("");
    };
    stagedRow.addEventListener("click", (e) => {
      const button = e.target.closest("[data-unstage]");
      if (!button) return;
      w.staged.splice(Number(button.dataset.unstage), 1);
      drawStaged();
    });
    w.stage = (name) => { w.staged.push(name); drawStaged(); w.input.focus(); };
    w.takeStaged = () => { const taken = w.staged; w.staged = []; drawStaged(); return taken; };
    const folderButton = $("#cc-folder");
    const modeButton = $("#cc-mode");
    const agentButton = $("#cc-agent");
    w.refresh = () => {
      folderButton.innerHTML = `${placeLabel(w.project, w.folder)}${icon("chevD", "chev")}`;
      folderButton.title = w.project ? `项目「${w.project}」：${projectSummary(projectByName(w.project))}` : "";
      modeButton.innerHTML = w.nextMode
        ? `${icon(MODES[w.nextMode].icon)}<span>${esc(w.mode)} → ${esc(w.nextMode)}</span>${icon("chevD", "chev")}`
        : `${icon(MODES[w.mode].icon)}<span>${esc(w.mode)}</span>${icon("chevD", "chev")}`;
      agentButton.innerHTML = `${agentTile(w.agent)}<span>${esc(AGENTS[w.agent].label)}</span>${icon("chevD", "chev")}`;
    };
    w.refresh();
    const applyPlace = ({ project: p = null, folder: f = null }) => {
      const changed = p !== w.project || f !== w.folder;
      w.project = p;
      w.folder = f;
      w.refresh();
      if (changed && w.tx.list.children.length) divider(w.tx, `位置改为「${p || f || "无文件夹"}」— 下一轮起在这里工作`);
    };
    w.pickPlace = (place) => {
      if (!w.busy) return applyPlace(place);
      w.nextPlace = place;
      flash("下一轮生效：正在进行的这一轮不会中途换位置");
    };
    w.newProject = async () => {
      const created = await newProjectDialog();
      if (!created || !node.isConnected) return;
      const aside = node.querySelector(".win-side");
      aside.querySelectorAll(".side-row.selected").forEach((r) => r.classList.remove("selected"));
      aside.querySelector(".side-search").insertAdjacentHTML("afterend", projectGroup({ project: { ...created, open: true }, rows: [{ id: "new", title: "新对话", selected: true }] }));
      w.pickPlace({ project: created.name });
      flash(`（原型）已新建项目「${created.name}」：${projectSummary(created)}`);
    };
    folderButton.addEventListener("click", () => openMenu(folderButton, placeMenu(w.project, w.folder, w.pickPlace, w.newProject), { placement: "above-left", wide: true }));
    // A rule never changes under a running turn: a switch made mid-turn waits for the next one.
    modeButton.addEventListener("click", () => openMenu(modeButton, modeMenu(w.nextMode || w.mode, async (name) => {
      if (name === (w.nextMode || w.mode)) return;
      if (name === "自动编辑" && !(await confirmAutoEdit(w.agent, w.folder))) return;
      if (w.busy) {
        w.nextMode = name === w.mode ? null : name;
        w.refresh();
        if (w.nextMode) flash("下一轮生效：正在进行的这一轮不会中途换规则");
        return;
      }
      w.mode = name;
      w.refresh();
    }), { placement: "above-left" }));
    agentButton.addEventListener("click", () => openMenu(agentButton, agentMenu(w.agent, (key) => {
      if (key === w.agent) return;
      w.agent = key;
      w.refresh();
      if (w.tx.list.children.length) divider(w.tx, `已切换到 ${AGENTS[key].label} — 新会话，前文以摘要带入`);
    }), { placement: "above-right" }));
    $("#cc-plus").addEventListener("click", (e) => openMenu(e.currentTarget, toolsMenu(), { placement: "above-left", wide: true }));
    w.setSend = (busy) => {
      const send = $("#cc-send");
      send.innerHTML = icon(busy ? "stop" : "arrowUp");
      send.setAttribute("aria-label", busy ? "停止" : "发送");
    };
    w.status = (id, status) => {
      const row = node.querySelector(`[data-chat="${id}"] .status`);
      if (row) row.innerHTML = status === "pending" ? '<span class="dot" title="等待确认"></span>' : status === "running" ? '<span class="spinner"></span>' : "";
      if (w.syncPending) w.syncPending();
    };
    // The dock floats over the transcript, so the transcript keeps its last line clear of it.
    const scroller = $("#win-scroll");
    w.syncDock = () => {
      scroller.style.paddingBottom = `${Math.max(24, w.dock.offsetHeight + 16)}px`;
      w.tx.keepUp();
    };
    $("#cc-send").addEventListener("click", () => { if (pending) decide("allow"); });
    w.endTurn = () => {
      w.busy = false;
      if (w.nextMode) { w.mode = w.nextMode; w.nextMode = null; w.refresh(); }
      if (w.nextPlace) { applyPlace(w.nextPlace); w.nextPlace = null; }
    };
    w.ask = async (spec) => {
      const card = approvalCard(spec);
      w.dock.appendChild(card);
      w.dock.classList.add("asking");
      w.syncDock();
      card.querySelectorAll("[data-act]").forEach((b) => b.addEventListener("click", () => decide(b.dataset.act)));
      const placeholder = w.input.placeholder;
      w.input.placeholder = spec.danger ? `点「${spec.allow}」确认，或输入其他指示…` : "↵ 允许，或输入其他指示…";
      w.input.focus();
      const decision = await ask(spec);
      w.input.placeholder = placeholder;
      card.classList.add("sink");
      setTimeout(() => { card.remove(); w.dock.classList.remove("asking"); w.syncDock(); }, 130);
      return decision;
    };
    node.querySelectorAll(".side-row").forEach((row) => row.addEventListener("click", () => {
      if (!row.classList.contains("selected")) flash("（原型）切到那段对话；有待确认的操作时，卡片就在输入框上沿等你");
    }));
    wireSidebar(w);
    return w;
  }

  // Collapsed stays reachable: the left edge slides it over the transcript, ⌘B pins it back.
  function wireSidebar(w) {
    const { node } = w;
    const side = node.querySelector(".win-side");
    const zone = node.querySelector(".edge-zone");
    let lastX = null;
    let dwell = 0;
    let closing = 0;
    const isPeeking = () => node.classList.contains("peek");
    const unpeek = () => {
      clearTimeout(dwell);
      clearTimeout(closing);
      node.classList.remove("peek");
      if (sidebarPeek === unpeek) sidebarPeek = null;
    };
    const closeSoon = () => { if (isPeeking()) closing = setTimeout(unpeek, 300); };
    // A folded project or a hidden sidebar still says that something inside it is waiting.
    w.syncPending = () => {
      node.classList.toggle("has-pending", Boolean(side.querySelector(".side-row .dot")));
      side.querySelectorAll(".proj").forEach((p) => {
        p.querySelector(".proj-dot").innerHTML = p.querySelector(".side-row .dot") ? '<span class="dot"></span>' : "";
      });
    };
    w.peek = () => {
      if (!state.sidebarCollapsed) return;
      clearTimeout(closing);
      node.classList.add("peek");
      sidebarPeek = unpeek;
    };
    w.toggleSidebar = () => {
      state.sidebarCollapsed = !state.sidebarCollapsed;
      unpeek();
      node.classList.toggle("collapsed", state.sidebarCollapsed);
      if (state.sidebarCollapsed) {
        flash(state.peekEnabled ? "侧边栏已收起：指针从窗口内移到左缘，它就会滑出来；⌘B 固定回来" : "侧边栏已收起；设置里关掉了悬停滑出，⌘B 显示");
      }
    };
    node.addEventListener("mousemove", (e) => { lastX = e.clientX - node.getBoundingClientRect().left; });
    node.addEventListener("mouseleave", () => { lastX = null; clearTimeout(dwell); closeSoon(); });
    zone.addEventListener("mouseenter", (e) => {
      // Arriving from outside the window, or mid-drag, is not a request for the sidebar.
      if (!state.peekEnabled || e.buttons || lastX === null || lastX <= zone.offsetWidth) return;
      dwell = setTimeout(w.peek, 100);
    });
    zone.addEventListener("mouseleave", () => clearTimeout(dwell));
    side.addEventListener("mouseenter", () => clearTimeout(closing));
    side.addEventListener("mouseleave", closeSoon);
    node.querySelector(".win-main").addEventListener("mousedown", () => { if (isPeeking()) unpeek(); });
    node.querySelector(".win-sidebar-btn").addEventListener("click", () => w.toggleSidebar());
    w.syncPending();
    activeWindow = w;
  }

  const toolsState = { web: true, servers: { "Tinycast · github": true, "Claude Code · lark": true, "Claude Code · bytedcli": true, "Claude Code · figma": false } };
  function toolsMenu() {
    return [
      { icon: "clip", label: "附加文件…", act: () => flash("（原型）附加文件：agent 模式下交给 agent 的是文件路径，由它自己的工具去读") },
      { icon: "crop", label: "截取屏幕…", act: () => activeWindow && activeWindow.stage("截屏 10.24.png") },
      { icon: "clipboard", label: "从剪贴板历史选图…", act: () => activeWindow && activeWindow.stage("剪贴板图片.png") },
      { icon: "globe", label: "联网搜索", check: toolsState.web, act: () => { toolsState.web = !toolsState.web; } },
      { sep: true },
      { head: "本次对话的工具" },
      ...Object.keys(toolsState.servers).map((name) => ({ icon: "plug", label: name, check: toolsState.servers[name], trail: name.endsWith("figma") ? ["未登录"] : undefined, act: () => { toolsState.servers[name] = !toolsState.servers[name]; } })),
      { icon: "wand", label: "Skills · 83 个可用", trail: ["排除…"], act: () => flash("（原型）打开可搜索的 skill 列表，取消勾选的只在这段对话里不用") },
      { note: "只影响这一段对话；默认值在 设置 › AI。" },
    ];
  }

  /* ---------- Scenes ---------- */

  const REPORT = "草稿写好了：\n· 本周完成：Agent 模式调研、发票整理脚本上线\n· 进行中：周报自动化（约 70%）\n· 下周计划：Agent 模式原型、接入 Codex";
  const DOC_SPEC = { icon: "docPlus", title: "创建飞书文档", sub: "lark-doc · 来自 Claude Code 的 skill", fields: [["标题", "第 42 周周报"], ["位置", "我的空间"], ["内容", "3 个小节 · 486 字"]], allow: "创建" };
  const UPDATE_SPEC = { icon: "pencil", title: "更新飞书文档", sub: "lark-doc · 第 42 周周报", fields: [["改动", "「下周计划」补充 3 条"]] };

  const scenes = [
    {
      id: "palette",
      nav: "01 面板快任务",
      caption: "⌥Space 呼出面板，一句话交给 agent；需要确认时，主操作就变成「允许 ↵」。",
      flow: ["面板快任务", "↵ 发送 → agent 工作 → ↵ 允许 → 完成，留一行可撤销的改动"],
      enter(t) {
        const p = makePalette(this, t);
        this.onKey = p.onKey;
        setControls([
          { label: "发送", kbd: "↵", run: () => p.send() },
          { label: "允许", kbd: "↵", run: () => decide("allow") },
          { label: "本次对话都允许", kbd: "⌥↵", run: () => decide("session") },
          { label: "输入其他指示", run: () => { p.input.value = "先别移，列个清单给我"; p.input.focus(); flash("在输入框按 ↵：拒绝这一步，并把这句话交给 agent"); } },
          { label: "操作菜单", kbd: "⌘K", run: () => openMenu($("#pal-actions"), p.actionItems(), { wide: true }) },
          { label: "收起面板", kbd: "⎋", run: () => p.onKey({ key: "Escape", metaKey: false }) },
        ]);
      },
    },
    {
      id: "window",
      nav: "02 窗口长任务",
      caption: "复杂任务在 AI Chat 窗口里跑：用你已有的 skills 和 MCP，确认卡片从输入框上沿升起。",
      flow: ["窗口长任务", "写周报：读日历、任务、纪要 → 确认创建飞书文档 → 给出链接"],
      enter(t) {
        const w = windowShell({
          title: "写第 42 周周报",
          sub: "周报",
          groups: chatGroups("report", { invoice: "pending" }),
          placeholder: "给 Claude Code 布置任务…",
          project: "周报",
        });
        const failure = state.failure;
        const ctx = { busy: false, queued: [], session: false };
        w.input.value = "根据这周的日历、任务和周会纪要写周报，放到飞书文档里";
        w.input.focus();

        const queue = (text) => {
          const chip = html(`<div class="queued glass">${icon("clock")}<span>排队中</span><b>${esc(text)}</b><button class="mini-btn" aria-label="移除">${icon("xmark")}</button></div>`);
          chip.classList.add("rise");
          w.dock.appendChild(chip);
          const item = { text, chip };
          ctx.queued.push(item);
          w.syncDock();
          chip.querySelector("button").addEventListener("click", () => { ctx.queued = ctx.queued.filter((q) => q !== item); chip.remove(); w.syncDock(); });
        };

        const followUp = async (text) => {
          w.tx.add(html(`<div class="msg-user">${esc(text)}</div>`));
          const work = working(w.tx);
          if (!(await wait(700, t))) return;
          work.done();
          if (ctx.session) {
            w.tx.add(line(icon("pencil"), "已更新飞书文档", "本次对话已允许，未再询问"));
          } else {
            w.status("report", "pending");
            const again = await w.ask(UPDATE_SPEC);
            if (!live(t)) return;
            w.status("report", "running");
            if (again.choice !== "allow" && again.choice !== "session") {
              w.tx.add(line(icon("xmark"), "已拒绝", "更新飞书文档", "t3"));
              return;
            }
            w.tx.add(line(icon("pencil"), "已更新飞书文档", "「下周计划」补充 3 条"));
          }
          await stream(w.tx, "下周计划已经补充好了。", t);
        };

        const run = async () => {
          const text = w.input.value.trim();
          if (!text || ctx.busy) return;
          ctx.busy = true;
          w.busy = true;
          w.input.value = "";
          w.input.placeholder = "↵ 排队到这一轮之后 · ⌘↵ 立即插话";
          w.setSend(true);
          w.status("report", "running");
          const shots = w.takeStaged();
          w.tx.add(html(`<div class="msg-user">${shots.map(() => '<span class="shot"></span>').join("")}${esc(text)}</div>`));
          const work = working(w.tx);
          const plan = makePlan(w.dock, ["收集本周的日历、任务和纪要", "起草周报", "创建飞书文档"], w.syncDock);
          if (!(await wait(500, t))) return;
          if (failure === "login") {
            work.done();
            await notice(w.tx, { title: "Claude Code 未登录", body: "在终端运行 claude 完成登录，然后重试。", action: "重试" });
            if (!live(t)) return;
            working(w.tx);
          }
          if (failure === "folder") flash("这个任务没有用文件夹：它只用 skills 和 MCP，不碰本机文件");
          const tools = toolRun(w.tx);
          if (!(await tools.call({ group: "skill", icon: "wand", verb: "使用技能", target: "lark-workflow-standup-report" }, t, 700))) return;
          if (!(await tools.call({ group: "read", icon: "calendar", verb: "读取日历", target: "本周 14 个日程" }, t, 650))) return;
          if (!(await tools.call({ group: "read", icon: "list", verb: "读取任务", target: "6 项进行中" }, t, 600))) return;
          if (!(await tools.call({ group: "read", icon: "doc", verb: "读取文档", target: "周会纪要 10-16", detail: "# 周会纪要 10-16\n- Agent 模式：确定「agent 当 infra」方向\n- 发票脚本：已上线，每月省 2 小时\n- 风险：飞书接口配额" }, t, 700))) return;
          tools.close();
          plan.next();
          await stream(w.tx, REPORT, t);
          if (!live(t)) return;
          plan.next();
          w.tx.pinned?.remove();
          w.tx.pinned = null;
          w.status("report", "pending");
          const decision = await w.ask(DOC_SPEC);
          if (!live(t)) return;
          w.status("report", "running");
          if (decision.choice === "deny" || decision.choice === "redirect") {
            w.tx.add(line(icon("xmark"), "已拒绝", "创建飞书文档", "t3"));
            if (decision.choice === "redirect") w.tx.add(html(`<div class="msg-user">${esc(decision.text)}</div>`));
            await stream(w.tx, decision.choice === "redirect" ? "好，改成先存一份本机草稿，等你确认后再发。" : "好的，草稿只留在这里，没有创建文档。", t);
          } else {
            ctx.session = decision.choice === "session";
            const doing = w.tx.add(line('<span class="spinner"></span>', "正在创建", "飞书文档"));
            if (!(await wait(900, t))) return;
            if (failure === "cmdfail") {
              doing.replaceWith(line(icon("warn"), "创建失败", "lark-doc：没有「我的空间」的写权限", "failed"));
              await stream(w.tx, "没有写权限。要不要改成保存到本机的 Markdown 文件？", t);
            } else {
              doing.replaceWith(line(icon("docPlus"), "已创建飞书文档", "第 42 周周报"));
              await stream(w.tx, "周报已创建。", t);
              if (!live(t)) return;
              w.tx.add(html(`<div><button class="chip glass">${icon("doc")}<span>第 42 周周报</span>${icon("open")}</button></div>`));
            }
          }
          if (!live(t)) return;
          plan.done();
          while (ctx.queued.length) {
            const next = ctx.queued.shift();
            next.chip.remove();
            w.syncDock();
            await followUp(next.text);
            if (!live(t)) return;
          }
          if (failure === "switch") {
            if (!(await wait(700, t))) return;
            w.agent = "codex";
            w.refresh();
            divider(w.tx, "已切换到 Codex · GPT-5.5 — 新会话，前文以摘要带入");
          }
          ctx.busy = false;
          w.endTurn();
          w.status("report", null);
          w.setSend(false);
          w.input.placeholder = `给 ${AGENTS[w.agent].short} 布置任务…`;
        };

        const steer = (text) => {
          w.tx.add(html(`<div class="msg-user">${esc(text)}</div>`));
          w.tx.add(line(icon("bubble"), "已插话", "agent 会在下一步调整", "t3"));
        };

        $("#cc-send").addEventListener("click", () => { if (!pending) run(); });
        this.onKey = (e) => {
          if (e.key !== "Enter" || e.shiftKey || e.altKey || pending) return false;
          if (ctx.busy) {
            const text = w.input.value.trim();
            if (text) { w.input.value = ""; if (e.metaKey) steer(text); else queue(text); }
            return true;
          }
          run();
          return true;
        };
        setControls([
          { label: "发送", kbd: "↵", run: () => run() },
          { label: "运行中排队一条", kbd: "↵", run: () => { if (!ctx.busy) return flash("先发送任务，agent 运行时再试"); queue("顺便把下周计划写细一点"); } },
          { label: "运行中插话", kbd: "⌘↵", run: () => { if (!ctx.busy) return flash("先发送任务，agent 运行时再试"); steer("周报语气正式一点"); } },
          { label: "允许", kbd: "↵", run: () => decide("allow") },
          { label: "本次对话都允许", kbd: "⌥↵", run: () => decide("session") },
          { label: "拒绝", kbd: "⎋", run: () => decide("deny") },
          { label: "换 agent", run: () => $("#cc-agent").click() },
          { label: "显示 / 收起侧边栏", kbd: "⌘B", run: () => activeWindow && activeWindow.toggleSidebar() },
          { label: "模拟悬停左缘", run: () => {
            if (!activeWindow) return;
            if (!state.sidebarCollapsed) activeWindow.toggleSidebar();
            setTimeout(() => activeWindow && activeWindow.peek(), 320);
          } },
          { label: "附加截图", run: () => activeWindow && activeWindow.stage("截屏 10.24.png") },
          { label: "新建项目", run: () => activeWindow && activeWindow.newProject() },
        ]);
      },
    },
    {
      id: "approval",
      nav: "03 授权",
      caption: "一张卡片承载所有授权：命令、改文件、删除、外部写操作；键盘一步完成。",
      flow: ["授权卡片", "↵ 允许 · ⌥↵ 本次对话都允许 · ⎋ 拒绝 · 直接输入＝拒绝并改口"],
      variants: {
        command: { ask: "跑一下测试，看看有没有挂的", say: "先运行测试脚本。", folder: "tinycast", spec: { icon: "terminal", title: "运行命令", sub: "Claude Code · 在「tinycast」中", code: [{ text: "./Scripts/run-tests.sh" }] } },
        edit: { ask: "把 AGENTS.md 里的系统版本要求改成 macOS 27", say: "需要改一处。", folder: "tinycast", spec: { icon: "pencil", title: "修改 AGENTS.md", sub: "+1 −1 · 在「tinycast」中", code: [{ text: "@@ Posture: modern-first @@" }, { cls: "del", text: "- Tinycast supports macOS 26 and later" }, { cls: "ins", text: "+ Tinycast supports macOS 27 and later" }] } },
        delete: { ask: "把下载里 2024 年的旧报表删掉", say: "找到 3 个文件。", folder: "下载", spec: { icon: "trash", danger: true, session: false, allow: "删除", title: "删除 3 个文件", sub: "在「下载」中", code: [{ text: "rm 旧报表-2024-*.xlsx" }], note: "会直接删除，不经过废纸篓，也无法从这里撤销" } },
        mcp: { ask: "告诉张三周报发了", say: "我来发一条飞书消息。", folder: null, spec: { icon: "paperplane", title: "发送飞书消息", sub: "lark-im · 来自 Claude Code 的 MCP", fields: [["发给", "张三"], ["内容", "周报已发到你的空间，有空看看 🙏"]], allow: "发送" } },
        multi: { ask: "把这三件事都办了", say: "需要确认 3 项操作。", folder: "tinycast" },
      },
      enter(t) {
        const scene = this;
        let variant = this.variant || "command";
        let w = null;
        const multi = [
          { icon: "pencil", title: "修改 README.md", sub: "+4 −0 · 在「tinycast」中", code: [{ cls: "ins", text: "+ ## Agent 模式" }, { cls: "ins", text: "+ 选 agent、选文件夹、选模式。" }] },
          { icon: "terminal", title: "运行命令", sub: "在「tinycast」中", code: [{ text: "./Scripts/lint.sh" }] },
          { icon: "paperplane", title: "发送飞书消息", sub: "lark-im · 来自 Claude Code 的 MCP", fields: [["发给", "研发群"], ["内容", "Agent 模式文档已更新"]], allow: "发送" },
        ];
        const show = async () => {
          closeMenu();
          root.innerHTML = "";
          const v = scene.variants[variant];
          w = windowShell({ title: "授权卡片", sub: variantLabel(variant), groups: [{ group: "今天", rows: [{ title: "授权卡片", selected: true }] }], placeholder: "给 Claude Code 布置任务…", folder: v.folder });
          w.tx.add(html(`<div class="msg-user">${esc(v.ask)}</div>`));
          w.tx.add(html(`<div class="msg-ai">${esc(v.say)}</div>`));
          const queue = variant === "multi" ? multi.map((s, i) => ({ ...s, count: `${i + 1} / ${multi.length}` })) : [v.spec];
          for (const spec of queue) {
            const decision = await w.ask(spec);
            if (!live(t)) return;
            const verdict = {
              allow: [icon("check"), "已允许"],
              session: [icon("checkCircle"), "本次对话都允许"],
              deny: [icon("xmark"), "已拒绝"],
              redirect: [icon("xmark"), "已拒绝"],
            }[decision.choice];
            w.tx.add(line(verdict[0], verdict[1], spec.title, decision.choice === "deny" || decision.choice === "redirect" ? "t3" : ""));
            if (decision.choice === "redirect") w.tx.add(html(`<div class="msg-user">${esc(decision.text)}</div>`));
            if (decision.choice === "session") w.tx.add(line("", `之后同类操作（${spec.title.replace(/ .*/, "")}）在这段对话里不再询问`, "", "t3"));
            if (!(await wait(450, t))) return;
          }
          if (!(await wait(900, t))) return;
          show();
        };
        const pick = (key) => { scene.variant = key; variant = key; token += 1; pending = null; closeMenu(); enterScene("approval", true); };
        show();
        setControls([
          ...Object.keys(this.variants).map((key) => ({ label: variantLabel(key), active: key === variant, run: () => pick(key) })),
          { label: "允许", kbd: "↵", run: () => decide("allow") },
          { label: "本次对话都允许", kbd: "⌥↵", run: () => decide("session") },
          { label: "拒绝", kbd: "⎋", run: () => decide("deny") },
          { label: "输入其他指示", run: () => { w.input.value = "先别动，告诉我会改哪些地方"; w.input.focus(); flash("在输入框按 ↵：拒绝这一步，并把这句话交给 agent"); } },
        ]);
        this.onKey = () => false;
      },
    },
    {
      id: "changes",
      nav: "04 改动审阅",
      caption: "每轮结束只留一行改动汇总；展开看清单、预览内容，可以整轮撤销。",
      flow: ["改动审阅", "汇总 → 展开 → 预览 → 撤销（撤销本身可恢复，所以不弹确认）"],
      enter(t) {
        const w = windowShell({
          title: "发票按月份重命名",
          sub: "发票整理",
          groups: chatGroups("invoice"),
          placeholder: "给 Claude Code 布置任务…",
          project: "发票整理",
        });
        const tx = w.tx;
        tx.add(html('<div class="msg-user">把下载里的发票 PDF 按「年月-商户」重命名，再汇总成一张表</div>'));
        const run = tx.add(html('<div class="run"></div>'));
        run.innerHTML = `<button class="toggle-line" type="button">${icon("wrench")}<span>查看了 1 个文件夹，读取了 12 处</span>${icon("chevD", "chev")}</button><div class="collapse"><div><div class="run-list">${callRow({ icon: "folder", verb: "查看", target: "下载 · 86 项" })}${callRow({ icon: "doc", verb: "读取", target: "scan_0012.pdf 等 12 个 PDF" })}</div></div></div>`;
        tx.add(line(icon("check"), "已允许", "重命名 12 个文件、新建 1 个文件"));
        tx.add(html('<div class="msg-ai">完成。12 张发票已按「年月-商户」重命名，汇总表是「发票汇总-2026.csv」。</div>'));
        const renames = [["2026-07-滴滴出行.pdf", "scan_0012.pdf"], ["2026-08-美团.pdf", "scan_0013.pdf"], ["2026-08-中国国航.pdf", "IMG_8823.pdf"], ["2026-09-京东.pdf", "发票(3).pdf"]];
        const changes = tx.add(html(`<div class="changes">
          <button class="toggle-line" type="button">${icon("pencil")}<span>改动了 13 个文件</span><span class="t3">重命名 12 · 新建 1</span>${icon("chevD", "chev")}</button>
          <div class="collapse"><div><div class="run-list">
            <div class="file-row" data-preview><span class="file-ic csv"></span><span class="fname">发票汇总-2026.csv</span><span class="stat add">新建 +13</span><span class="row-actions"><button class="mini-btn">打开</button><button class="mini-btn">在访达中显示</button></span></div>
            <div class="preview" hidden><div class="code">${["日期,商户,金额,文件", "2026-07-03,滴滴出行,46.20,2026-07-滴滴出行.pdf", "2026-08-11,美团,128.00,2026-08-美团.pdf", "2026-08-19,中国国航,1460.00,2026-08-中国国航.pdf", "……共 12 行"].map((l, i) => `<div class="${i < 4 ? "ins" : ""}">${i < 4 ? "+ " : "  "}${esc(l)}</div>`).join("")}</div></div>
            ${renames.map(([to, from]) => `<div class="file-row"><span class="file-ic pdf"></span><span class="fname">${esc(to)}</span><span class="stat">原名 ${esc(from)}</span><span class="row-actions"><button class="mini-btn">打开</button><button class="mini-btn">在访达中显示</button></span></div>`).join("")}
            <div class="file-row"><span class="stat">还有 8 个重命名</span></div>
            <button class="mini-btn undo" data-undo>${icon("uturn")} 撤销这些改动</button>
          </div></div></div></div>`));
        const undo = () => {
          if (changes.isConnected) undoInPlace(changes, "已撤销 13 处改动", "12 个文件改回原名，汇总表移到废纸篓", () => {});
        };
        changes.querySelector("[data-undo]").addEventListener("click", undo);
        const preview = changes.querySelector("[data-preview]");
        preview.addEventListener("click", (e) => {
          if (e.target.closest("button")) return;
          preview.classList.toggle("selected");
          preview.nextElementSibling.hidden = !preview.classList.contains("selected");
        });
        this.onKey = () => false;
        setControls([
          { label: "展开改动", run: () => changes.classList.add("open") },
          { label: "预览汇总表", run: () => { changes.classList.add("open"); preview.click(); } },
          { label: "撤销这些改动", run: () => { changes.classList.add("open"); undo(); } },
          { label: "重置", run: () => enterScene("changes") },
        ]);
      },
    },
    {
      id: "background",
      nav: "05 后台提醒",
      caption: "面板收起后任务继续跑；要你确认或做完了，用 HUD 叫你回来，菜单栏图标也会亮一个点。",
      flow: ["后台提醒", "发送 → ⎋ 收起面板 → 等待确认 HUD → 查看 → ↵ 允许 → 完成 HUD"],
      enter(t) {
        const p = makePalette(this, t, { autoHideAfterDone: true });
        this.onKey = p.onKey;
        setControls([
          { label: "发送", kbd: "↵", run: () => p.send() },
          { label: "收起面板", kbd: "⎋", run: () => p.onKey({ key: "Escape", metaKey: false }) },
          { label: "点 HUD「查看」", run: () => { const button = root.querySelector(".hud-btn"); if (button) button.click(); else flash("等「等待确认」的 HUD 出现后再点"); } },
          { label: "允许", kbd: "↵", run: () => decide("allow") },
        ]);
        flash("先 ↵ 发送，然后马上按 ⎋ 收起面板，看任务在后台继续");
      },
    },
    {
      id: "settings",
      nav: "06 设置与技能",
      caption: "按 agent 勾选是否复用它自己的 skills、MCP、插件和 Hooks；会话里还能单独排除。",
      flow: ["设置与技能", "设置 › AI 勾选默认值 → 输入框「+」按会话排除"],
      enter(t) {
        const view = this.view || "settings";
        if (view === "session") {
          const w = windowShell({ title: "写第 42 周周报", sub: "周报", groups: chatGroups("report"), placeholder: "给 Claude Code 布置任务…", project: "周报" });
          w.tx.add(html('<div class="msg-user">根据这周的日历、任务和周会纪要写周报，放到飞书文档里</div>'));
          setTimeout(() => { if (live(t)) $("#cc-plus").click(); }, 250);
        } else {
          renderSettings();
        }
        this.onKey = () => false;
        setControls([
          { label: "设置页", active: view === "settings", run: () => { this.view = "settings"; enterScene("settings"); } },
          { label: "会话工具菜单", active: view === "session", run: () => { this.view = "session"; enterScene("settings"); } },
        ]);
      },
    },
  ];

  function variantLabel(key) {
    return { command: "运行命令", edit: "修改文件", delete: "删除", mcp: "外部写操作", multi: "多个待确认" }[key];
  }

  const SKILLS = [
    ["lark-doc", "飞书云文档：读取、创建、编辑"],
    ["lark-im", "飞书消息：收发消息、管理群聊"],
    ["lark-calendar", "飞书日历：查看和创建日程"],
    ["lark-workflow-standup-report", "日程待办摘要"],
    ["bytedcli", "内部研发平台的命令行"],
    ["bits-env", "测试环境管理与服务部署"],
    ["argos", "可观测与诊断"],
    ["figma:figma-use", "操作 Figma 文件"],
  ];

  function renderSettings() {
    const enabled = new Set(SKILLS.map(([name]) => name).filter((n) => n !== "bits-env"));
    const node = html(`<div class="settings">
      <aside class="set-side"><div class="traffic"><i></i><i></i><i></i></div>${["通用", "外观", "快捷键", "剪贴板", "截图", "AI", "扩展", "关于"].map((n) => `<button class="side-row${n === "AI" ? " selected" : ""}"><span class="title">${n}</span></button>`).join("")}</aside>
      <section class="set-main">
        <div class="set-title">AI</div>
        <div class="set-section">已安装的 agent</div>
        <div class="card">
          ${providerRow("#d97757", "✳", "Claude Code", "已登录 · 2.3.1", true)}
          ${providerRow("#1f1f22", "◎", "Codex", "已登录 · 0.162.1", true)}
          ${providerRow("#3b3bd6", "π", "pi", "未安装 · 安装后自动出现", false, true)}
        </div>
        <div class="set-section">Claude Code</div>
        <div class="card">
          <div class="form-row"><div class="meta"><b>默认模式</b><span>新对话从这里开始，输入框里随时可改</span></div><div class="trail"><span class="popup">询问 ${icon("chevUD")}</span></div></div>
          <div class="form-row"><div class="meta"><b>常用文件夹</b><span>下载、tinycast、项目资料</span></div><div class="trail"><button class="mini-btn">管理…</button></div></div>
        </div>
        <div class="set-section">复用 Claude Code 自己的配置</div>
        <div class="card" id="reuse">
          <div class="form-row"><div class="meta"><b>Skills</b><span id="skill-count">${enabled.size} / 83 个启用 · 来自 ~/.agents/skills</span></div><div class="trail"><button class="mini-btn" id="pick-skills">选择…</button><button class="switch on" data-switch></button></div></div>
          <div id="skill-panel" hidden><div class="skill-search">${icon("search")}<input id="skill-filter" placeholder="搜索 skill" style="border:0;outline:0;background:none;flex:1;font-size:12px;color:var(--t1)"></div><div class="skill-list" id="skill-list"></div></div>
          <div class="form-row"><div class="meta"><b>MCP 服务器</b><span>lark、bytedcli、figma · 来自你的 Claude Code 配置</span></div><div class="trail"><button class="mini-btn">选择…</button><button class="switch on" data-switch></button></div></div>
          <div class="form-row"><div class="meta"><b>插件</b><span>4 个已安装</span></div><div class="trail"><button class="switch" data-switch></button></div></div>
          <div class="form-row"><div class="meta"><b>Hooks</b><span>每次工具调用前后运行你配置的脚本</span></div><div class="trail"><button class="switch" data-switch></button></div></div>
        </div>
        <p class="set-caption">打开后，Tinycast 里的 Claude Code 会加载你在终端里用的这些配置。用它们改东西时，照样先在 Tinycast 里问你。这些开关不进入备份，也不写进 settings.json。</p>
        <div class="set-section">AI Chat 窗口</div>
        <div class="card">
          <div class="form-row"><div class="meta"><b>收起的侧边栏在指针移到左缘时滑出</b><span>⌘B 显示或隐藏侧边栏；滑出后再按 ⌘B 就固定</span></div><div class="trail"><button class="switch${state.peekEnabled ? " on" : ""}" id="peek-switch"></button></div></div>
        </div>
      </section>
    </div>`);
    root.appendChild(node);
    node.querySelectorAll("[data-switch]").forEach((s) => s.addEventListener("click", () => s.classList.toggle("on")));
    $("#peek-switch").addEventListener("click", (e) => {
      state.peekEnabled = !state.peekEnabled;
      e.currentTarget.classList.toggle("on", state.peekEnabled);
    });
    const list = $("#skill-list");
    const draw = (filter = "") => {
      list.innerHTML = SKILLS.filter(([name, desc]) => `${name}${desc}`.includes(filter)).map(([name, desc]) => `<div class="skill-row" data-skill="${esc(name)}"><span class="checkbox${enabled.has(name) ? " on" : ""}">${icon("check")}</span><span>${esc(name)}</span><span class="desc">${esc(desc)}</span></div>`).join("") || '<div class="skill-row"><span class="desc">没有匹配的 skill</span></div>';
      $("#skill-count").textContent = `${enabled.size + 75} / 83 个启用 · 来自 ~/.agents/skills`;
    };
    list.addEventListener("click", (e) => {
      const row = e.target.closest("[data-skill]");
      if (!row) return;
      const name = row.dataset.skill;
      if (enabled.has(name)) enabled.delete(name); else enabled.add(name);
      draw($("#skill-filter").value.trim());
    });
    $("#skill-filter").addEventListener("input", (e) => draw(e.target.value.trim()));
    $("#pick-skills").addEventListener("click", () => { $("#skill-panel").hidden = !$("#skill-panel").hidden; });
    draw();
  }

  function providerRow(color, glyph, name, status, on, disabled = false) {
    return `<div class="form-row"><span class="provider-tile" style="background:${color}">${glyph}</span><div class="meta"><b>${esc(name)}</b><span>${esc(status)}</span></div><div class="trail"><button class="switch${on ? " on" : ""}${disabled ? " disabled" : ""}"${disabled ? "" : " data-switch"}></button></div></div>`;
  }

  /* ---------- Review chrome ---------- */

  function setControls(items) {
    controls.innerHTML = "";
    for (const item of items) {
      const button = html(`<button type="button"${item.active ? ' style="background:#1d1d20;color:#fff;border-color:#1d1d20"' : ""}>${esc(item.label)}${item.kbd ? `<kbd>${esc(item.kbd)}</kbd>` : ""}</button>`);
      button.addEventListener("click", item.run);
      controls.appendChild(button);
    }
  }

  function enterScene(id, keepVariant = false) {
    token += 1;
    for (const id_ of timers) { clearTimeout(id_); }
    timers.clear();
    pending = null;
    modal = null;
    activeWindow = null;
    sidebarPeek = null;
    closeMenu();
    menubarBadge.classList.remove("pending");
    root.innerHTML = "";
    const scene = scenes.find((s) => s.id === id) || scenes[0];
    current = scene;
    state.scene = scene.id;
    nav.querySelectorAll("button").forEach((b) => b.setAttribute("aria-current", String(b.dataset.scene === scene.id)));
    caption.textContent = scene.caption;
    flowLabel.textContent = scene.flow[0];
    flowDetail.textContent = scene.flow[1];
    scene.enter(token);
  }

  for (const scene of scenes) {
    const button = html(`<button type="button" data-scene="${scene.id}">${esc(scene.nav)}</button>`);
    button.addEventListener("click", () => enterScene(scene.id));
    nav.appendChild(button);
  }

  root.addEventListener("click", (e) => {
    const add = e.target.closest(".proj-add");
    if (add) {
      flash(`（原型）在「${add.closest(".proj").dataset.project}」里新建对话：文件夹、默认 agent 和模式都按项目来`);
      return;
    }
    const head = e.target.closest(".proj-head");
    if (head) {
      head.parentElement.classList.toggle("open");
      return;
    }
    const toggle = e.target.closest(".toggle-line");
    if (toggle) {
      toggle.parentElement.classList.toggle("open");
      return;
    }
    const row = e.target.closest(".line.has-detail");
    if (row && row.nextElementSibling) row.nextElementSibling.hidden = !row.nextElementSibling.hidden;
  });

  document.addEventListener("keydown", (e) => {
    if (modal) {
      if (e.key === "Enter") { e.preventDefault(); modal.finish(true); }
      else if (e.key === "Escape") { e.preventDefault(); modal.finish(false); }
      return;
    }
    if (e.key === "Escape" && closeMenu()) { e.preventDefault(); return; }
    if (e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "b") {
      if (activeWindow) { e.preventDefault(); activeWindow.toggleSidebar(); }
      return;
    }
    if (e.key === "Escape" && sidebarPeek) { e.preventDefault(); sidebarPeek(); return; }
    if (current && current.onKey && current.onKey(e)) { e.preventDefault(); return; }
    if (!pending) return;
    if (e.key === "Enter" && !e.shiftKey && !e.metaKey) {
      e.preventDefault();
      if (e.altKey) return decide("session");
      const input = document.activeElement && /^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName) ? document.activeElement : null;
      const text = input ? input.value.trim() : "";
      if (text && input.id !== "skill-filter") { input.value = ""; decide("redirect", text); }
      else if (pending.spec.danger) flash(`「${pending.spec.title}」不接受 ↵：请点按钮确认，避免顺手按掉`);
      else decide("allow");
    } else if (e.key === "Escape") {
      e.preventDefault();
      decide("deny");
    }
  });

  $("#theme-toggle").addEventListener("click", (e) => {
    const dark = studio.dataset.theme === "dark";
    studio.dataset.theme = dark ? "light" : "dark";
    e.currentTarget.textContent = dark ? "深色外观" : "浅色外观";
  });
  $("#apply-failure").addEventListener("click", () => {
    state.failure = failureSelect.value;
    const target = state.failure === "none" ? state.scene : ["palette", "window"].includes(state.scene) ? state.scene : "palette";
    enterScene(target);
  });
  failureSelect.addEventListener("change", () => { state.failure = failureSelect.value; });

  enterScene("palette");
})();
