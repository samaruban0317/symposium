// AI Coder (vibe-coding) webview script.
// The webview NEVER talks to a model — the extension host owns the StudioSession
// and posts { type:"providers" | "event" | "busy" | "error" } messages. We post
// back { type:"ready" | "send" | "approve" | "stop" | "reset" }.
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();

  const el = {
    provider: document.getElementById("provider"),
    newChat: document.getElementById("newChat"),
    agentMode: document.getElementById("agentMode"),
    planFirst: document.getElementById("planFirst"),
    transcript: document.getElementById("transcript"),
    input: document.getElementById("input"),
    send: document.getElementById("send"),
    stop: document.getElementById("stop"),
    vibe: document.getElementById("vibe"),
    vibeText: document.getElementById("vibeText")
  };

  // The assistant bubble currently receiving streamed text (null between turns).
  let streamBubble = null;
  let busy = false;

  // ---- Vibe meter ------------------------------------------------------------
  let vibeIdleTimer = null;
  function setVibe(tps) {
    el.vibeText.textContent = (tps || 0).toFixed(1) + " tok/s";
    el.vibe.className = "vibe vibe--live";
    if (vibeIdleTimer) clearTimeout(vibeIdleTimer);
    vibeIdleTimer = setTimeout(idleVibe, 1200);
  }
  function idleVibe() {
    el.vibe.className = "vibe vibe--idle";
  }

  // ---- Transcript helpers ----------------------------------------------------
  function scrollDown() {
    el.transcript.scrollTop = el.transcript.scrollHeight;
  }

  function addBubble(role, text) {
    const div = document.createElement("div");
    div.className = "bubble bubble--" + role;
    div.textContent = text || "";
    el.transcript.appendChild(div);
    scrollDown();
    return div;
  }

  function ensureStreamBubble() {
    if (!streamBubble) {
      streamBubble = addBubble("assistant", "");
      streamBubble.classList.add("cursor");
    }
    return streamBubble;
  }

  function endStream() {
    if (streamBubble) streamBubble.classList.remove("cursor");
    streamBubble = null;
  }

  function appendText(text) {
    const b = ensureStreamBubble();
    b.textContent += text;
    scrollDown();
  }

  // ---- Plan + approval cards -------------------------------------------------
  function renderPlan(steps) {
    endStream();
    const card = document.createElement("div");
    card.className = "card";
    const title = document.createElement("div");
    title.className = "card-title";
    title.textContent = "Plan";
    card.appendChild(title);

    const ol = document.createElement("ol");
    (steps || []).forEach(function (s) {
      const li = document.createElement("li");
      li.textContent = s;
      ol.appendChild(li);
    });
    card.appendChild(ol);
    el.transcript.appendChild(card);
    scrollDown();
    // A plan is informational; approval (if required) arrives as its own
    // approvalRequest event, so we do not add buttons here.
  }

  function renderApproval(id, summary, detail) {
    endStream();
    const card = document.createElement("div");
    card.className = "card";

    const title = document.createElement("div");
    title.className = "card-title";
    title.textContent = "Approval needed";
    card.appendChild(title);

    const sum = document.createElement("div");
    sum.className = "summary";
    sum.textContent = summary || "";
    card.appendChild(sum);

    if (detail) {
      const pre = document.createElement("pre");
      pre.textContent = detail;
      card.appendChild(pre);
    }

    const actions = document.createElement("div");
    actions.className = "card-actions";
    const approve = document.createElement("button");
    approve.className = "btn btn--approve";
    approve.textContent = "Approve";
    const reject = document.createElement("button");
    reject.className = "btn btn--reject";
    reject.textContent = "Reject";
    actions.appendChild(approve);
    actions.appendChild(reject);
    card.appendChild(actions);

    const verdict = document.createElement("div");
    verdict.className = "card-verdict";
    verdict.hidden = true;
    card.appendChild(verdict);

    function decide(ok) {
      vscode.postMessage({ type: "approve", id: id, ok: ok });
      card.classList.add("card--resolved");
      verdict.hidden = false;
      verdict.textContent = ok ? "✓ Approved" : "✕ Rejected";
    }
    approve.addEventListener("click", function () {
      decide(true);
    });
    reject.addEventListener("click", function () {
      decide(false);
    });

    el.transcript.appendChild(card);
    scrollDown();
  }

  function renderToolResult(name, result) {
    endStream();
    result = result || {};
    const det = document.createElement("details");
    det.className = "tool " + (result.ok === false ? "tool--fail" : "tool--ok");
    const sum = document.createElement("summary");
    sum.textContent = "🔧 tool: " + (name || "unknown");
    det.appendChild(sum);
    const body = result.display || result.content || "";
    if (body) {
      const pre = document.createElement("pre");
      pre.textContent = body;
      det.appendChild(pre);
    }
    el.transcript.appendChild(det);
    scrollDown();
  }

  // ---- SessionEvent dispatch -------------------------------------------------
  function onEvent(ev) {
    if (!ev || typeof ev.kind !== "string") return;
    switch (ev.kind) {
      case "text":
        appendText(ev.text || "");
        break;
      case "tokPerSec":
        setVibe(ev.value);
        break;
      case "status":
        // "thinking"/"streaming" keep the meter alive; "done"/"error" let it dim.
        if (ev.status === "error" && ev.detail) addBubble("error", ev.detail);
        break;
      case "toolCall":
        // The call itself is quiet; its toolResult renders the compact line.
        break;
      case "toolResult":
        renderToolResult(ev.name, ev.result);
        break;
      case "plan":
        renderPlan(ev.steps);
        break;
      case "approvalRequest":
        renderApproval(ev.id, ev.summary, ev.detail);
        break;
      case "turnDone":
        endStream();
        break;
    }
  }

  // ---- Providers -------------------------------------------------------------
  function renderProviders(providers, defaultId) {
    el.provider.innerHTML = "";
    (providers || []).forEach(function (p) {
      const opt = document.createElement("option");
      opt.value = p.id;
      const needsKey = p.needsKey && !p.available;
      opt.textContent = p.label + (needsKey ? " — add a key" : "");
      opt.disabled = !p.available;
      if (p.id === defaultId) opt.selected = true;
      el.provider.appendChild(opt);
    });
  }

  // ---- Sending ---------------------------------------------------------------
  function setBusy(v) {
    busy = v;
    el.send.disabled = v;
    el.stop.hidden = !v;
    if (!v) {
      endStream();
      idleVibe();
    }
  }

  function doSend() {
    if (busy) return;
    const text = el.input.value.trim();
    if (!text) return;
    const providerId = el.provider.value || "local";
    addBubble("user", text);
    el.input.value = "";
    vscode.postMessage({
      type: "send",
      text: text,
      providerId: providerId,
      agentMode: el.agentMode.checked,
      planFirst: el.planFirst.checked
    });
    setBusy(true);
  }

  el.send.addEventListener("click", doSend);
  el.stop.addEventListener("click", function () {
    vscode.postMessage({ type: "stop" });
  });
  el.newChat.addEventListener("click", function () {
    vscode.postMessage({ type: "reset" });
    el.transcript.innerHTML = "";
    endStream();
    idleVibe();
  });

  el.input.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      doSend();
    }
  });

  // ---- Host -> webview -------------------------------------------------------
  window.addEventListener("message", function (event) {
    const msg = event.data;
    if (!msg) return;
    switch (msg.type) {
      case "providers":
        renderProviders(msg.providers, msg.defaultId);
        break;
      case "event":
        onEvent(msg.event);
        break;
      case "busy":
        setBusy(!!msg.busy);
        break;
      case "error":
        endStream();
        addBubble("error", msg.message || "Something went wrong.");
        break;
    }
  });

  vscode.postMessage({ type: "ready" });
})();
