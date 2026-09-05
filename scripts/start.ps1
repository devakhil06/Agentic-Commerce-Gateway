param([switch]$Build)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
$taskPython = Join-Path $taskRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $taskPython)) {
    python -m venv .venv
    & $taskPython -m pip install -r backend/requirements.lock
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
}
if ($Build -or -not (Test-Path -LiteralPath 'frontend\build\web\index.html')) {
    Push-Location -LiteralPath 'frontend'
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed.' }
        flutter build web --release --pwa-strategy=none
        if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
    } finally { Pop-Location }
}
& $taskPython -m alembic upgrade head
if ($LASTEXITCODE -ne 0) { throw 'Database migration failed.' }
Write-Host 'Open http://127.0.0.1:8080 to use the gateway.'
& $taskPython -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8080
