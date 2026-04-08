# E-Governance Platform - Start in background (Docker)
# Run this when you come back - no need to keep terminal open.
# Then open http://localhost:8000/dashboard/

$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

Set-Location $root
Write-Host "Starting E-Governance Platform in background..." -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done. Open in browser:  http://localhost:8000/dashboard/" -ForegroundColor Green
    Write-Host "To stop later, run:  docker compose down" -ForegroundColor Yellow
} else {
    Write-Host "Failed. Is Docker Desktop running?" -ForegroundColor Red
}
