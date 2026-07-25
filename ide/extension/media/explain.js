// Explain panel webview script.
// The webview never calls a model — the extension host owns the StudioSession
// and the active editor. This script just: picks an audience, asks the host to
// explain / diagram, streams text deltas into the answer, and renders any
// Mermaid the host detects (with a graceful <pre> fallback when mermaid is
// unavailable).
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();
  const state = vscode.getState() || {};
  let audience = state.audience || "student";
  let busy = false;

  const el = {
    audBtns: Array.prototype.slice.call(document.querySelectorAll(".aud")),
    ctx: document.getElementById("ctx"),
    explainFile: document.getElementById("explainFile"),
    explainSel: document.getElementById("explainSel"),
    diagram: document.getElementById("diagram"),
    hint: document.getElementById("hint"),
    answer: document.getElementById("answer"),
    thinking: document.getElementById("thinking"),
    diagramWrap: document.getElementById("diagramWrap"),
    mermaid: document.getElementById("mermaid"),
    err: document.getElementById("err")
  };

  // ---- Mermaid setup (graceful) ----------------------------------------
  let mermaidReady = false;
  if (window.mermaid && typeof window.mermaid.initialize === "function") {
    try {
      window.mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "dark" });
      mermaidReady = true;
    } catch (_e) {
      mermaidReady = false;
    }
  }
  let diagramSeq = 0;

  // ---- audience control ------------------------------------------------
  function setAudience(next) {
    audience = next;
    vscode.setState(Object.assign({}, vscode.getState(), { audience: audience }));
    el.audBtns.forEach(function (b) {
      const on = b.getAttribute("data-aud") === audience;
      b.classList.toggle("is-on", on);
      b.setAttribute("aria-checked", on ? "true" : "false");
    });
  }
  el.audBtns.forEach(function (b) {
    b.addEventListener("click", function () {
      const next = b.getAttribute("data-aud");
      const changed = next !== audience;
      setAudience(next);
      // Changing the audience re-explains at the new depth if we have an answer.
      if (changed && el.answer.textContent && !busy) {
        request({ type: "explain", scope: lastScope, audience: audience });
      }
    });
  });
  setAudience(audience);

  // ---- actions ----------------------------------------------------------
  let lastScope = "file";

  function request(msg) {
    if (busy) return;
    clearError();
    if (msg.type === "explain") lastScope = msg.scope;
    vscode.postMessage(msg);
  }

  el.explainFile.addEventListener("click", function () {
    request({ type: "explain", scope: "file", audience: audience });
  });
  el.explainSel.addEventListener("click", function () {
    request({ type: "explain", scope: "selection", audience: audience });
  });
  el.diagram.addEventListener("click", function () {
    request({ type: "diagram", audience: audience });
  });

  // ---- rendering --------------------------------------------------------
  function startAnswer() {
    el.hint.hidden = true;
    el.answer.hidden = false;
    el.answer.textContent = "";
    el.thinking.hidden = false;
  }

  function appendText(t) {
    el.answer.textContent += t;
  }

  function endAnswer() {
    el.thinking.hidden = true;
    if (!el.answer.textContent) {
      // Nothing came back — restore the friendly hint.
      el.answer.hidden = true;
      el.hint.hidden = false;
    }
  }

  function renderMermaid(code) {
    el.diagramWrap.hidden = false;
    if (mermaidReady) {
      const id = "mmd" + ++diagramSeq;
      try {
        // mermaid v10/11 render returns a promise ({ svg }).
        const p = window.mermaid.render(id, code);
        Promise.resolve(p)
          .then(function (res) {
            el.mermaid.innerHTML = (res && res.svg) || res || "";
          })
          .catch(function () {
            mermaidFallback(code, "Couldn't draw the diagram, so here's the recipe for it:");
          });
        return;
      } catch (_e) {
        // fall through to fallback
      }
    }
    mermaidFallback(
      code,
      "Diagram engine isn't loaded, so here's the diagram description you can paste into any Mermaid viewer:"
    );
  }

  function mermaidFallback(code, note) {
    el.mermaid.innerHTML = "";
    const p = document.createElement("p");
    p.className = "mermaid-note";
    p.textContent = note;
    const pre = document.createElement("pre");
    pre.className = "mermaid-fallback";
    pre.textContent = code;
    el.mermaid.appendChild(p);
    el.mermaid.appendChild(pre);
  }

  function setBusy(b) {
    busy = b;
    el.explainFile.disabled = b;
    el.explainSel.disabled = b;
    el.diagram.disabled = b;
  }

  function showError(m) {
    el.err.hidden = false;
    el.err.textContent = m;
  }
  function clearError() {
    el.err.hidden = true;
    el.err.textContent = "";
  }

  function updateContext(msg) {
    if (!msg.hasEditor) {
      el.ctx.textContent = "No file open yet.";
      el.explainFile.disabled = true;
      el.explainSel.disabled = true;
      el.diagram.disabled = true;
      return;
    }
    const sel = msg.hasSelection ? " · text selected" : "";
    el.ctx.textContent = "Looking at: " + (msg.fileName || "untitled") + sel;
    if (!busy) {
      el.explainFile.disabled = false;
      el.explainSel.disabled = !msg.hasSelection;
      el.diagram.disabled = false;
    }
  }

  // ---- host messages ----------------------------------------------------
  window.addEventListener("message", function (event) {
    const msg = event.data;
    if (!msg || typeof msg.type !== "string") return;

    switch (msg.type) {
      case "context":
        updateContext(msg);
        break;

      case "busy":
        setBusy(msg.busy);
        if (msg.busy) startAnswer();
        else endAnswer();
        break;

      case "event": {
        const ev = msg.event;
        if (!ev) break;
        if (ev.kind === "text" && typeof ev.text === "string") appendText(ev.text);
        else if (ev.kind === "status" && ev.status === "error") showError(ev.detail || "Something went wrong.");
        // turnDone / other kinds: nothing extra to do here; host handles mermaid.
        break;
      }

      case "mermaid":
        if (typeof msg.code === "string" && msg.code.trim()) renderMermaid(msg.code.trim());
        break;

      case "error":
        setBusy(false);
        endAnswer();
        showError(msg.message || "Something went wrong.");
        break;
    }
  });

  vscode.postMessage({ type: "ready" });
})();
