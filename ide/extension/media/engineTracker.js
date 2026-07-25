// Engine Tracker webview script.
// The webview NEVER opens a socket — the extension host owns it and posts
// { type:'metric', metric } and { type:'status', status, detail } messages.
(function () {
  "use strict";

  const vscode = acquireVsCodeApi();

  const MAX_POINTS = 120; // sliding window of loss samples for the chart

  // Restore any persisted loss history across webview reloads.
  const persisted = vscode.getState() || {};
  let lossHistory = Array.isArray(persisted.lossHistory) ? persisted.lossHistory : [];

  const el = {
    status: document.getElementById("status"),
    statusText: document.getElementById("statusText"),
    statusDetail: document.getElementById("statusDetail"),
    lossValue: document.getElementById("lossValue"),
    lossLine: document.getElementById("lossLine"),
    epoch: document.getElementById("epoch"),
    step: document.getElementById("step"),
    temp: document.getElementById("temp"),
    tps: document.getElementById("tps"),
    vramText: document.getElementById("vramText"),
    vramFill: document.getElementById("vramFill")
  };

  const CHART_W = 300;
  const CHART_H = 90;
  const PAD = 4;

  function drawChart() {
    if (lossHistory.length === 0) {
      el.lossLine.setAttribute("points", "");
      return;
    }
    let min = Infinity;
    let max = -Infinity;
    for (const v of lossHistory) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    const range = max - min || 1;
    const n = lossHistory.length;
    const stepX = n > 1 ? (CHART_W - PAD * 2) / (n - 1) : 0;

    const points = lossHistory
      .map((v, i) => {
        const x = PAD + i * stepX;
        // Higher loss -> higher on chart (invert y since SVG y grows downward).
        const y = PAD + (1 - (v - min) / range) * (CHART_H - PAD * 2);
        return x.toFixed(1) + "," + y.toFixed(1);
      })
      .join(" ");
    el.lossLine.setAttribute("points", points);
  }

  function fmt(v, digits) {
    if (v === undefined || v === null || Number.isNaN(v)) return "—";
    return typeof v === "number" ? v.toFixed(digits) : String(v);
  }

  function setStatus(status, detail) {
    const cls = "status status--" + status;
    el.status.className = cls;
    el.statusText.textContent = status;
    el.statusDetail.textContent = detail || "";
  }

  function applyMetric(m) {
    if (typeof m.loss === "number" && Number.isFinite(m.loss)) {
      lossHistory.push(m.loss);
      if (lossHistory.length > MAX_POINTS) {
        lossHistory = lossHistory.slice(lossHistory.length - MAX_POINTS);
      }
      el.lossValue.textContent = m.loss.toFixed(4);
      drawChart();
      vscode.setState({ lossHistory: lossHistory });
    }

    if (m.epoch !== undefined) el.epoch.textContent = fmt(m.epoch, 0);
    if (m.step !== undefined) el.step.textContent = fmt(m.step, 0);
    if (m.gpuTempC !== undefined) el.temp.textContent = fmt(m.gpuTempC, 0) + "°C";
    if (m.tokPerSec !== undefined) el.tps.textContent = fmt(m.tokPerSec, 1);

    if (typeof m.vramUsedMb === "number" && typeof m.vramTotalMb === "number" && m.vramTotalMb > 0) {
      const pct = Math.max(0, Math.min(100, (m.vramUsedMb / m.vramTotalMb) * 100));
      el.vramFill.style.width = pct.toFixed(1) + "%";
      el.vramFill.classList.toggle("hot", pct >= 90);
      el.vramText.textContent =
        Math.round(m.vramUsedMb) + " / " + Math.round(m.vramTotalMb) + " MB (" + pct.toFixed(0) + "%)";
    }
  }

  window.addEventListener("message", function (event) {
    const msg = event.data;
    if (!msg) return;
    if (msg.type === "metric" && msg.metric) {
      applyMetric(msg.metric);
    } else if (msg.type === "status") {
      setStatus(msg.status, msg.detail);
    }
  });

  // Paint any restored history, then tell the host we're ready for a status snapshot.
  drawChart();
  vscode.postMessage({ type: "ready" });
})();
