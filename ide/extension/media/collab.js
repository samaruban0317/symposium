// "Team & Git" webview script.
// The webview NEVER touches git or the network — the extension host owns both
// and posts { type:"state", ... } and { type:"toast", ... }. We only render and
// post back the user's intent. Strict CSP; no inline handlers.
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();

  const el = {
    branch: document.getElementById("branch"),
    saveMsg: document.getElementById("saveMsg"),
    saveBtn: document.getElementById("saveBtn"),
    saveState: document.getElementById("saveState"),
    roomName: document.getElementById("roomName"),
    roomEmail: document.getElementById("roomEmail"),
    newRoomBtn: document.getElementById("newRoomBtn"),
    joinCode: document.getElementById("joinCode"),
    joinBtn: document.getElementById("joinBtn"),
    noRoom: document.getElementById("noRoom"),
    hasRoom: document.getElementById("hasRoom"),
    roomLabel: document.getElementById("roomLabel"),
    roomCode: document.getElementById("roomCode"),
    roleLine: document.getElementById("roleLine"),
    mrCard: document.getElementById("mrCard"),
    mrTitle: document.getElementById("mrTitle"),
    openMrBtn: document.getElementById("openMrBtn"),
    mrList: document.getElementById("mrList"),
    timeline: document.getElementById("timeline"),
    timelineEmpty: document.getElementById("timelineEmpty"),
    toast: document.getElementById("toast"),
  };

  let toastTimer = null;

  // ---- Send helpers ----
  function send(type, extra) {
    vscode.postMessage(Object.assign({ type: type }, extra || {}));
  }

  el.saveBtn.addEventListener("click", function () {
    send("save", { message: el.saveMsg.value });
    el.saveMsg.value = "";
  });
  el.newRoomBtn.addEventListener("click", function () {
    send("createRoom", { name: el.roomName.value, email: el.roomEmail.value });
  });
  el.joinBtn.addEventListener("click", function () {
    send("joinRoom", { code: el.joinCode.value, email: el.roomEmail.value });
  });
  el.openMrBtn.addEventListener("click", function () {
    send("openMr", { title: el.mrTitle.value });
    el.mrTitle.value = "";
  });

  // ---- Render ----
  function render(s) {
    el.branch.textContent = s.branch || "…";

    // Save button only makes sense inside a project.
    el.saveBtn.disabled = !s.isRepo;
    if (!s.isRepo) {
      el.saveState.textContent = "Open a folder to start saving your work.";
    } else if (s.clean) {
      el.saveState.textContent = "Everything is saved. ✓";
    } else {
      el.saveState.textContent = s.changedCount + " change(s) waiting to be saved.";
    }

    // Room block.
    if (s.room) {
      el.noRoom.hidden = true;
      el.hasRoom.hidden = false;
      el.roomLabel.textContent = s.room.name;
      el.roomCode.textContent = s.room.joinCode;
      el.roleLine.textContent = s.myRole
        ? "You are a " + s.myRole + " in this room."
        : "Connected.";
      el.mrCard.hidden = false;
    } else {
      el.noRoom.hidden = false;
      el.hasRoom.hidden = true;
      el.mrCard.hidden = true;
    }

    renderMergeRequests(s);
    renderTimeline(s.commits || []);
  }

  function renderMergeRequests(s) {
    el.mrList.textContent = "";
    if (s.relayOffline) {
      const li = document.createElement("li");
      li.className = "offline-note";
      li.textContent = "Relay not reachable — team features are offline right now.";
      el.mrList.appendChild(li);
      return;
    }
    const list = s.mergeRequests || [];
    if (list.length === 0) {
      const li = document.createElement("li");
      li.className = "tiny";
      li.textContent = "No merge requests yet.";
      el.mrList.appendChild(li);
      return;
    }
    for (const mr of list) {
      el.mrList.appendChild(mrCard(mr, s.isAdmin));
    }
  }

  function mrCard(mr, isAdmin) {
    const li = document.createElement("li");
    li.className = "mr-item";

    const head = document.createElement("div");
    head.className = "mr-head";
    const title = document.createElement("span");
    title.className = "mr-title";
    title.textContent = mr.title || "(untitled)";
    const status = document.createElement("span");
    status.className = "mr-status " + (mr.status || "open");
    status.textContent = mr.status || "open";
    head.appendChild(title);
    head.appendChild(status);

    const meta = document.createElement("p");
    meta.className = "mr-meta";
    meta.textContent =
      "by " + (mr.author || "?") + " · branch " + (mr.branch || "?") +
      (mr.diffSummary ? " · " + mr.diffSummary : "");

    li.appendChild(head);
    li.appendChild(meta);

    // Only the admin sees Approve / Reject, and only while the MR is open.
    if (isAdmin && mr.status === "open") {
      const actions = document.createElement("div");
      actions.className = "mr-actions";
      const approve = document.createElement("button");
      approve.className = "btn btn-approve";
      approve.textContent = "✓ Approve";
      approve.addEventListener("click", function () {
        send("approveMr", { id: mr.id });
      });
      const reject = document.createElement("button");
      reject.className = "btn btn-reject";
      reject.textContent = "✕ Send back";
      reject.addEventListener("click", function () {
        send("rejectMr", { id: mr.id });
      });
      actions.appendChild(approve);
      actions.appendChild(reject);
      li.appendChild(actions);
    }
    return li;
  }

  function renderTimeline(commits) {
    el.timeline.textContent = "";
    el.timelineEmpty.hidden = commits.length > 0;
    for (const c of commits) {
      const li = document.createElement("li");
      li.className = "commit";

      const subj = document.createElement("div");
      subj.className = "commit-subject";
      subj.textContent = c.subject || "(no message)";

      const meta = document.createElement("div");
      meta.className = "commit-meta";
      const hash = document.createElement("span");
      hash.className = "commit-hash";
      hash.textContent = c.hash || "";
      meta.appendChild(hash);
      meta.appendChild(document.createTextNode(" · " + (c.author || "?") + " · " + (c.date || "")));

      li.appendChild(subj);
      li.appendChild(meta);
      el.timeline.appendChild(li);
    }
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
