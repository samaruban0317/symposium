# Symposium dev environment bootstrap (Windows PowerShell).
#   Right-click > Run with PowerShell, or:  pwsh -File scripts/setup_env.ps1
# Idempotent: safe to re-run. Sets up the lab Python venv + .env files.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Write-Host "== Symposium setup ==  ($repo)" -ForegroundColor Cyan

function Check($name, $cmd) {
    $ok = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($ok) { Write-Host "  [ok]   $name -> $($ok.Source)" -ForegroundColor Green }
    else     { Write-Host "  [MISS] $name — install it, then re-run" -ForegroundColor Yellow }
    return [bool]$ok
}

Write-Host "`nChecking tools:"
Check "Flutter" "flutter" | Out-Null
Check "Dart"    "dart"    | Out-Null
Check "Ollama"  "ollama"  | Out-Null
$hasPy311 = $false
try { & py -3.11 --version *> $null; $hasPy311 = ($LASTEXITCODE -eq 0) } catch {}
if ($hasPy311) { Write-Host "  [ok]   Python 3.11" -ForegroundColor Green }
else { Write-Host "  [MISS] Python 3.11 — the ML lab needs 3.11 (not 3.13/3.14)" -ForegroundColor Yellow }

# --- lab venv + deps (RAG, CPU-only) ---
if ($hasPy311) {
    $venv = Join-Path $repo "lab\.venv"
    if (-not (Test-Path $venv)) {
        Write-Host "`nCreating lab venv (Python 3.11)..." -ForegroundColor Cyan
        & py -3.11 -m venv $venv
    }
    & "$venv\Scripts\python.exe" -m pip install --upgrade pip
    & "$venv\Scripts\python.exe" -m pip install -r (Join-Path $repo "lab\requirements.txt")
    Write-Host "  lab RAG deps installed. Activate with: lab\.venv\Scripts\Activate.ps1" -ForegroundColor Green
}

# --- .env from .env.example (never overwrite a real one) ---
foreach ($pair in @(@("lab\.env.example","lab\.env"), @("deploy\symposium-host.env.example","deploy\symposium-host.env"))) {
    $ex = Join-Path $repo $pair[0]; $dst = Join-Path $repo $pair[1]
    if ((Test-Path $ex) -and (-not (Test-Path $dst))) {
        Copy-Item $ex $dst
        Write-Host "  created $($pair[1]) — fill in the placeholders" -ForegroundColor Green
    }
}

Write-Host "`nDone. Next: cd lab; python rag_pipeline.py ingest ./data" -ForegroundColor Cyan
