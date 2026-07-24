# Symposium releases — runbook

This folder holds the CI that turns a **git tag** into published, downloadable
builds. Read this once; after that, cutting a release is two commands.

## Cut a release (the whole flow)

1. Bump the version in `app/pubspec.yaml` (e.g. `version: 0.2.3`) and commit it.
2. Tag and push:

   ```bash
   git tag v0.2.3
   git push --tags
   ```

That's it. Pushing a `v*` tag triggers `.github/workflows/release.yml`, which:

1. **setup** — reads the version from the tag (`v0.2.3` → `0.2.3`) and stamps an
   ISO 8601 UTC time (`released_at`).
2. **build-windows / build-linux / build-android** — three jobs run in parallel,
   each `cd app`, `flutter pub get`, build, and package:
   - Windows → `Symposium-0.2.3-windows.zip`
   - Linux → `Symposium-0.2.3-linux.tar.gz`
   - Android → `Symposium-0.2.3-android.apk`
3. **release** — creates/updates the GitHub Release for the tag, attaches those
   three files **plus `downloads-manifest.json`**, then **prunes** the repo to
   the newest 3 releases.

You can also run it by hand from the **Actions → Release → Run workflow** button
(it asks for a version, since there's no tag in that case).

No secrets to configure — GitHub's built-in `GITHUB_TOKEN` is all it uses.

> Note: `app/windows` and `app/linux` may not be committed. The workflow (and the
> local scripts) run `flutter create --platforms=<os> .` before building, which
> regenerates the desktop runner if it's missing. Harmless no-op if it's present.

## Local one-command builds

Mirror the CI on your own machine (handy for testing before tagging):

- **Windows host:** `pwsh scripts/build_release.ps1` → builds Windows + Android into `dist/`.
- **Linux host:** `bash scripts/build_release.sh` → builds Linux + Android into `dist/`.

Both read the version from `app/pubspec.yaml`, write versioned filenames, and
print the resulting file list. (No single machine can build all three desktop
targets — Windows needs Windows, Linux needs Linux. CI does all three.)

## What `downloads-manifest.json` is for

The company site (`visionarysparks.in/downloads`) should **not** be hard-coded to
a version. Instead it fetches this one small JSON from the latest GitHub Release
and renders whatever it finds. Shape:

```json
{
  "latest": {
    "version": "0.2.3",
    "released_at": "2026-07-24T18:40:00Z",
    "windows_url": "https://github.com/<owner>/symposium/releases/download/v0.2.3/Symposium-0.2.3-windows.zip",
    "linux_url":   "https://github.com/<owner>/symposium/releases/download/v0.2.3/Symposium-0.2.3-linux.tar.gz",
    "android_url": "https://github.com/<owner>/symposium/releases/download/v0.2.3/Symposium-0.2.3-android.apk"
  },
  "versions": [
    { "version": "0.2.3", "released_at": "...", "windows_url": "...", "linux_url": "...", "android_url": "..." },
    { "version": "0.2.2", "released_at": "...", "windows_url": "...", "linux_url": "...", "android_url": "..." },
    { "version": "0.2.1", "released_at": "...", "windows_url": "...", "linux_url": "...", "android_url": "..." }
  ]
}
```

- `latest` = the current build (with its exact release timestamp).
- `versions` = up to the **3 most recent** builds (current + previous 2), newest
  first. The download URLs use GitHub's permanent
  `.../releases/download/<tag>/<file>` redirect, so they're stable.

## Pruning to 3

Each release run, after publishing, lists all releases newest-first and **deletes
every release past the 3rd** (with `gh release delete --cleanup-tag`, so the old
git tag goes too). So the repo never accumulates more than the current + previous
2 builds, matching what the site shows.

---

## Backend change (visionary-backend — DO THIS THERE, not here)

The site's downloads page lives in the **separate** `visionary-backend` repo
(`C:\Users\Samaruban V\OneDrive\Desktop\visionary-backend`). It currently serves
a static `/download` page and `/symposium` page (registered via the
`PUBLIC_PAGES` list in `main.py` around **line 4811-4814**), and there's an
existing manifest-proxy precedent right above it: `@app.get("/sandbox/latest.json")`
at **main.py line 4718**.

**Minimal change:** add one route that fetches Symposium's
`downloads-manifest.json` from the latest GitHub Release and returns it (cached),
so the `/download` page's JS can call a same-origin endpoint (no CORS) and render
the latest-3 buttons.

Add this near the `/sandbox/latest.json` handler (~line 4733) in
`visionary-backend/main.py`. It uses **only stdlib** (`os`, `time`, `json`,
`urllib.request`, `JSONResponse` — all already imported at the top of `main.py`),
so there is **no new dependency** to add to `requirements.txt`:

```python
# Symposium download manifest — proxied from its GitHub Release so the /download
# page can fetch a same-origin, cached JSON (no CORS, no code redeploy per release).
# Set SYMPOSIUM_MANIFEST_URL to override the source; the default points at the
# latest release's downloads-manifest.json asset.
_symposium_manifest_cache = {"at": 0.0, "data": None}

@app.get("/downloads/symposium-manifest.json")
def symposium_manifest():
    url = os.getenv(
        "SYMPOSIUM_MANIFEST_URL",
        "https://github.com/samaruban0317/symposium/releases/latest/download/downloads-manifest.json",
    )
    now = time.time()
    # 5-minute in-process cache — GitHub is the source of truth; don't hammer it.
    if _symposium_manifest_cache["data"] and now - _symposium_manifest_cache["at"] < 300:
        return JSONResponse(_symposium_manifest_cache["data"],
                            headers={"Cache-Control": "public, max-age=300"})
    try:
        # urllib follows the releases/latest/download 302 redirect automatically.
        req = urllib.request.Request(url, headers={"User-Agent": "visionarysparks"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        _symposium_manifest_cache.update(at=now, data=data)
        return JSONResponse(data, headers={"Cache-Control": "public, max-age=300"})
    except Exception:
        # Serve the last good copy if GitHub hiccups; else an empty shell.
        if _symposium_manifest_cache["data"]:
            return JSONResponse(_symposium_manifest_cache["data"])
        return JSONResponse({"latest": None, "versions": []}, status_code=503)
```

Then in the `/download` page's frontend JS (the `download.html` template built by
`tools/build_pages.py`), fetch `('/downloads/symposium-manifest.json')` and render
one row per entry in `versions` with three links (`windows_url`, `linux_url`,
`android_url`) and the `released_at` date. The top card uses `latest`.

`urllib.request.urlopen` follows the 302 that `releases/latest/download/...`
issues to the actual asset, so no extra flag is needed. Optionally set
`SYMPOSIUM_MANIFEST_URL` on Cloud Run to pin a specific tag; the default already
points at "latest".

> This is documentation only — no change was made to `visionary-backend`. Confirm
> the GitHub owner/repo slug in the default URL matches the real Symposium repo
> (`samaruban0317/symposium`).
