// Model Marketplace webview script.
// The webview NEVER touches the network — the extension host owns all I/O and
// pushes catalog/installed/progress messages in. We render + post intents.
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();

  const el = {
    endpoint: document.getElementById("endpoint"),
    connectBtn: document.getElementById("connectBtn"),
    pullName: document.getElementById("pullName"),
    pullBtn: document.getElementById("pullBtn"),
    search: document.getElementById("search"),
    installed: document.getElementById("installed"),
    catalog: document.getElementById("catalog")
  };

  // Local view state.
  let catalog = []; // CatalogModel[]
  let installed = []; // { name, size, details }[]
  let installedNames = new Set();
  let query = "";
  // name -> { barEl, fillEl, noteEl, btnEl }  (card handles while pulling)
  const cards = new Map();

  function fmtSize(bytes) {
    if (typeof bytes !== "number" || bytes <= 0) return "";
    const gb = bytes / 1e9;
    if (gb >= 1) return gb.toFixed(1) + " GB";
    return Math.max(1, Math.round(bytes / 1e6)) + " MB";
  }

  function matches(text) {
    return !query || text.toLowerCase().indexOf(query) !== -1;
  }

  // ---- Rendering ---------------------------------------------------------

  function render() {
    renderInstalled();
    renderCatalog();
  }

  function renderInstalled() {
    el.installed.textContent = "";
    const rows = installed.filter((m) => matches(m.name));
    if (rows.length === 0) {
      el.installed.appendChild(emptyEl(installed.length ? "No matches." : "No models installed yet."));
      return;
    }
    for (const m of rows) {
      const sub = [fmtSize(m.size), m.details && m.details.parameter_size, m.details && m.details.quantization_level]
        .filter(Boolean)
        .join(" · ");
      el.installed.appendChild(
        modelCard({ name: m.name, tag: "installed", sub: sub, desc: "", installed: true })
      );
    }
  }

  function renderCatalog() {
    el.catalog.textContent = "";
    const rows = catalog.filter((c) => matches(c.name + " " + c.label + " " + c.goodFor));
    if (rows.length === 0) {
      el.catalog.appendChild(emptyEl("No matches."));
      return;
    }
    for (const c of rows) {
      const isIn = installedNames.has(c.name);
      el.catalog.appendChild(
        modelCard({
          name: c.name,
          title: c.label,
          tag: isIn ? "installed" : "",
          sub: [c.size, c.goodFor].filter(Boolean).join(" · "),
          desc: c.description,
          installed: isIn
        })
      );
    }
  }

  function emptyEl(text) {
    const p = document.createElement("p");
    p.className = "empty";
    p.textContent = text;
    return p;
  }

  // Build one model card. Returns the card element and registers its handles.
  function modelCard(opts) {
    const card = document.createElement("div");
    card.className = "model";

    const head = document.createElement("div");
    head.className = "model-head";

    const nameWrap = document.createElement("div");
    const name = document.createElement("span");
    name.className = "model-name";
    name.textContent = opts.title || opts.name;
    nameWrap.appendChild(name);
    if (opts.tag) {
      const tag = document.createElement("span");
      tag.className = "tag";
      tag.textContent = opts.tag;
      name.appendChild(tag);
    }
    if (opts.title) {
      const idLine = document.createElement("div");
      idLine.className = "model-sub mono";
      idLine.textContent = opts.name;
      nameWrap.appendChild(idLine);
    }
    head.appendChild(nameWrap);

    if (opts.sub) {
      const sub = document.createElement("span");
      sub.className = "model-sub";
      sub.textContent = opts.sub;
      head.appendChild(sub);
    }
    card.appendChild(head);

    if (opts.desc) {
      const desc = document.createElement("p");
      desc.className = "model-desc";
      desc.textContent = opts.desc;
      card.appendChild(desc);
    }

    const actions = document.createElement("div");
    actions.className = "model-actions";

    const note = document.createElement("span");
    note.className = "status-note grow";

    const btn = document.createElement("button");
    btn.className = "primary";
    btn.textContent = opts.installed ? "Re-download" : "Download";
    btn.addEventListener("click", () => startPull(opts.name, card));

    actions.appendChild(note);
    actions.appendChild(btn);
    card.appendChild(actions);

    const bar = document.createElement("div");
    bar.className = "bar";
    const fill = document.createElement("div");
    fill.className = "bar-fill";
    bar.appendChild(fill);
    card.appendChild(bar);

    // If a pull is already active for this model, re-attach live handles.
    if (cards.has(opts.name)) {
      const prev = cards.get(opts.name);
      note.textContent = prev.lastStatus || "";
      note.className = "status-note grow";
      bar.classList.add("show");
      applyFill(fill, prev.lastPercent);
      btn.disabled = true;
    }
    cards.set(opts.name, {
      barEl: bar,
      fillEl: fill,
      noteEl: note,
      btnEl: btn,
      lastStatus: cards.has(opts.name) ? cards.get(opts.name).lastStatus : "",
      lastPercent: cards.has(opts.name) ? cards.get(opts.name).lastPercent : undefined,
      active: cards.has(opts.name) ? cards.get(opts.name).active : false
    });

    return card;
  }

  function applyFill(fill, percent) {
    if (typeof percent === "number") {
      fill.classList.remove("indeterminate");
      fill.style.width = Math.max(0, Math.min(100, percent)).toFixed(1) + "%";
    } else {
      fill.classList.add("indeterminate");
    }
  }

  // ---- Actions -----------------------------------------------------------

  function startPull(name, card) {
    const h = cards.get(name);
    if (h && h.active) return;
    if (h) {
      h.active = true;
      h.btnEl.disabled = true;
      h.noteEl.className = "status-note grow";
      h.noteEl.textContent = "starting…";
      h.barEl.classList.add("show");
      applyFill(h.fillEl, undefined);
    }
    vscode.postMessage({ type: "pull", name: name });
  }

  function startFreePull() {
    const name = (el.pullName.value || "").trim();
    if (!name) return;
    vscode.postMessage({ type: "pull", name: name });
    el.pullName.value = "";
  }

  // ---- Host → webview ----------------------------------------------------

  function onProgress(msg) {
    const h = cards.get(msg.name);
    if (!h) return; // card not currently rendered (filtered out) — ignore
    h.active = true;
    h.btnEl.disabled = true;
    h.barEl.classList.add("show");
    h.lastStatus = msg.status || "";
    h.lastPercent = typeof msg.percent === "number" ? msg.percent : undefined;
    h.noteEl.className = "status-note grow";
    let label = h.lastStatus;
    if (typeof msg.percent === "number") label += " · " + msg.percent.toFixed(0) + "%";
    h.noteEl.textContent = label;
    applyFill(h.fillEl, h.lastPercent);
  }

  function onDone(name) {
    const h = cards.get(name);
    if (h) {
      h.active = false;
      h.btnEl.disabled = false;
      h.noteEl.className = "status-note grow ok";
      h.noteEl.textContent = "Downloaded ✓";
      applyFill(h.fillEl, 100);
      cards.delete(name);
    }
  }

  function onError(name, message) {
    const h = cards.get(name);
    if (h) {
      h.active = false;
      h.btnEl.disabled = false;
      h.barEl.classList.remove("show");
      h.noteEl.className = "status-note grow err";
      h.noteEl.textContent = message || "Download failed.";
      cards.delete(name);
    }
  }

  window.addEventListener("message", function (event) {
    const msg = event.data;
    if (!msg || !msg.type) return;
    switch (msg.type) {
      case "catalog":
        catalog = Array.isArray(msg.models) ? msg.models : [];
        renderCatalog();
        break;
      case "installed":
        installed = Array.isArray(msg.models) ? msg.models : [];
        installedNames = new Set(installed.map((m) => m.name));
        el.endpoint.className = "detail";
        el.endpoint.textContent = msg.endpoint
          ? "Connected to " + msg.endpoint + " · " + installed.length + " model(s) installed"
          : installed.length + " model(s) installed";
        render();
        break;
      case "error":
        el.endpoint.className = "detail err";
        el.endpoint.textContent = msg.message || "Could not reach a model engine.";
        break;
      case "pull:progress":
        onProgress(msg);
        break;
      case "pull:done":
        onDone(msg.name);
        break;
      case "pull:error":
        onError(msg.name, msg.message);
        break;
    }
  });

  // ---- Wire-up -----------------------------------------------------------

  el.connectBtn.addEventListener("click", () => vscode.postMessage({ type: "connectGpu" }));
  el.pullBtn.addEventListener("click", startFreePull);
  el.pullName.addEventListener("keydown", (e) => {
    if (e.key === "Enter") startFreePull();
  });
  el.search.addEventListener("input", () => {
    query = (el.search.value || "").trim().toLowerCase();
    render();
  });

  vscode.postMessage({ type: "ready" });
})();
