#Requires -Version 5.1
# Detiene todos los procesos del sistema

$PROJ = Split-Path $MyInvocation.MyCommand.Path
$pidsFile = Join-Path $PROJ ".pids.json"

Write-Host "`e[33m→ Deteniendo sistema...`e[0m"

if (Test-Path $pidsFile) {
  $pids = Get-Content $pidsFile | ConvertFrom-Json
  foreach ($prop in $pids.PSObject.Properties) {
    $pid = [int]$prop.Value
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) { Stop-Process -Id $pid -Force; Write-Host "`e[32m✓`e[0m $($prop.Name) (PID $pid) detenido" }
  }
  Remove-Item $pidsFile -Force
} else {
  # Fallback: matar por nombre
  Get-Process -Name node,ngrok,ollama -ErrorAction SilentlyContinue | Stop-Process -Force
  Write-Host "`e[32m✓`e[0m Procesos node/ngrok/ollama detenidos"
}
Write-Host "`e[32m✓`e[0m Sistema detenido"
