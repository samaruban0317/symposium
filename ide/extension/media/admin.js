// Room Admin webview script — the "WiFi-router settings" page for a team.
// The extension host owns the network (RelayClient); we only render the roster
// and post back role/credit changes. The admin token is never shown or stored
// here. Strict CSP; no inline handlers.
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();

  const el = {
    signInCard: document.getElementById("signInCard"),
    adminToken: document.getElementById("adminToken"),
    signInBtn: document.getElementById("signInBtn"),
    noRoomCard: document.getElementById("noRoomCard"),
    statsCard: document.getElementById("statsCard"),
    inFlight: document.getElementById("inFlight"),
    todayTotal: document.getElementById("todayTotal"),
    uniqueUsers: document.getElementById("uniqueUsers"),
    rosterCard: document.getElementById("rosterCard"),
    roster: document.getElementById("roster"),
    rosterEmpty: document.getElementById("rosterEmpty"),
    offlineNote: document.getElementById("offlineNote"),
    toast: document.getElementById("toast"),
  };

  let toastTimer = null;

  el.signInBtn.addEventListener("click", function () {
    const token = el.adminToken.value;
    el.adminToken.value = ""; // don't leave the secret in the field
    vscode.postMessage({ type: "signIn", token: token });
  });

  function render(s) {
    // Three exclusive states: need admin token → need room → full controls.
    if (!s.isAdmin) {
      show(el.signInCard, true);
      show(el.noRoomCard, false);
      show(el.statsCard, false);
      show(el.rosterCard, false);
      return;
    }
    show(el.signInCard, false);
    if (!s.hasRoom) {
      show(el.noRoomCard, true);
      show(el.statsCard, false);
      show(el.rosterCard, false);
      return;
    }
    show(el.noRoomCard, false);
    show(el.statsCard, true);
    show(el.rosterCard, true);

    renderStats(s.stats);
    renderRoster(s.roster || [], s.relayOffline);
  }

  function renderStats(stats) {
    el.inFlight.textContent = stats ? String(stats.inFlight) : "—";
    el.todayTotal.textContent = stats ? String(stats.todayTotal) : "—";
    el.uniqueUsers.textContent = stats ? String(stats.uniqueUsersToday) : "—";
  }

  function renderRoster(roster, offline) {
    el.offlineNote.hidden = !offline;
    el.roster.textContent = "";
    el.rosterEmpty.hidden = roster.length > 0 || offline;
    for (const m of roster) {
      el.roster.appendChild(memberRow(m));
    }
  }

  function memberRow(m) {
    const li = document.createElement("li");
    li.className = "member";

    const top = document.createElement("div");
    top.className = "member-top";

    const email = document.createElement("span");
    email.className = "member-email";
    email.textContent = m.email || m.guestId || "guest";
    email.title = email.textContent;

    const role = document.createElement("select");
    role.className = "role-select";
    for (const r of ["admin", "committer", "viewer"]) {
      const opt = document.createElement("option");
      opt.value = r;
      opt.textContent = r;
      if (m.role === r) opt.selected = true;
      role.appendChild(opt);
    }
    role.addEventListener("change", function () {
      vscode.postMessage({ type: "setRole", email: m.email, role: role.value });
    });

    top.appendChild(email);
    top.appendChild(role);

    const credits = document.createElement("div");
    credits.className = "credits";
    credits.appendChild(creditField("AI / day", m.aiCreditsPerDay, function (v) {
      vscode.postMessage({ type: "setCredits", email: m.email, aiCreditsPerDay: v });
    }));
    credits.appendChild(creditField("Commits / day", m.commitsPerDay, function (v) {
      vscode.postMessage({ type: "setCredits", email: m.email, commitsPerDay: v });
    }));

    li.appendChild(top);
    li.appendChild(credits);
    return li;
  }

  function creditField(label, value, onCommit) {
    const wrap = document.createElement("label");
    wrap.className = "credit-field";
    const lab = document.createElement("span");
    lab.className = "credit-label";
    lab.textContent = label;
    const input = document.createElement("input");
    input.className = "credit-input";
    input.type = "number";
    input.min = "0";
    input.value = String(value);
    // Commit on Enter or blur so we don't spam the relay on each keystroke.
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") input.blur();
    });
    input.addEventListener("change", function () {
      const n = parseInt(input.value, 10);
      onCommit(Number.isFinite(n) && n >= 0 ? n : 0);
    });
    wrap.appendChild(lab);
    wrap.appendChild(input);
    return wrap;
  }

  function show(node, on) {
    node.hidden = !on;
  }

  function showToast(level, text) {
    el.toast.className = "toast " + level;
    el.toast.textContent = text;
    el.toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el.toast.hidden = true;
    }, 4000);
  }

  window.addEventListener("message", function (event) {
    const msg = event.data;
    if (!msg) return;
    if (msg.type === "state") render(msg);
    else if (msg.type === "toast") showToast(msg.level || "info", msg.text || "");
  });

  vscode.postMessage({ type: "ready" });
})();
