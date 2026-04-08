# E-Governance Platform - Start all services (Windows, no Docker)
# Run this script from PowerShell, or right-click -> Run with PowerShell.
# It opens 3 windows: Citizen Service, Notification Service, API Gateway.

$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

Write-Host "Starting e-governance services (3 windows will open)..." -ForegroundColor Cyan
Write-Host "When all show 'Uvicorn running', open:  http://localhost:8000/dashboard/" -ForegroundColor Green
Write-Host ""

$cmd1 = @"
cd "$root\services\citizen-service"
`$env:NOTIFICATION_SERVICE_URL='http://localhost:8002'
pip install -q -r requirements.txt 2>`$null
Write-Host 'Citizen Service - port 8001' -ForegroundColor Yellow
uvicorn main:app --reload --port 8001
pause
"@

$cmd2 = @"
cd "$root\services\notification-service"
pip install -q -r requirements.txt 2>`$null
Write-Host 'Notification Service - port 8002' -ForegroundColor Yellow
uvicorn main:app --reload --port 8002
pause
"@

$cmd3 = @"
cd "$root\services\api-gateway"
pip install -q -r requirements.txt 2>`$null
Write-Host 'API Gateway + Dashboard - port 8000' -ForegroundColor Yellow
Write-Host 'Open http://localhost:8000/dashboard/' -ForegroundColor Green
uvicorn main:app --reload --port 8000
pause
"@

Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd1
Start-Sleep -Seconds 1
Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd2
Start-Sleep -Seconds 1
Start-Process powershell -ArgumentList "-NoExit", "-Command", $cmd3

Write-Host "Done. Three PowerShell windows should have opened." -ForegroundColor Cyan
Write-Host "Wait until each shows 'Uvicorn running on http://...', then open:" -ForegroundColor White
Write-Host "  http://localhost:8000/dashboard/" -ForegroundColor Green
