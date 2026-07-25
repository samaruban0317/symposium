# media/vendor

Third-party scripts vendored for **offline, CSP-safe** loading inside webviews.
The strict CSP forbids remote script loads, so everything a panel needs must
live here and be referenced via `renderPanelHtml({ extraScripts: [...] })`.

## mermaid.min.js

- **Package:** [`mermaid`](https://www.npmjs.com/package/mermaid)
- **Version vendored:** `11.16.0` (the `mermaid@11` UMD/global build)
- **Source:** https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
- **Global exposed:** `window.mermaid` (the build assigns `globalThis["mermaid"]`).

Used by the Explain panel to render workflow flowcharts from a ` ```mermaid `
block the model emits.

### To re-vendor / upgrade

```bash
curl -sSL -o mermaid.min.js "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
```

`explain.js` degrades gracefully: if `window.mermaid` is missing or
`render()` throws, it shows the raw Mermaid code in a `<pre>` with a short note,
so the panel never breaks even without this file.
