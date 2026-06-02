#Requires -Version 5.1
# ================================================================
#  start-windows.ps1 — Inicia sistema Concentrados Monserrath
#  Uso: .\start-windows.ps1
# ================================================================

$ErrorActionPreference = 'Continue'
$PROJ   = Split-Path $MyInvocation.MyCommand.Path
$SERVER = Join-Path $PROJ "server"
$LOG    = Join-Path $PROJ "logs"
$NODE   = "$env:USERPROFILE\scoop\apps\nodejs20\current\node.exe"
$NGROK  = "$env:USERPROFILE\scoop\shims\ngrok.exe"
$OLLAMA = "$env:USERPROFILE\scoop\shims\ollama.exe"

$G = "`e[32m"; $Y = "`e[33m"; $R = "`e[31m"; $B = "`e[1m"; $NC = "`e[0m"
function ok($m)   { Write-Host "${G}✓${NC} $m" }
function warn($m) { Write-Host "${Y}⚠${NC}  $m" }
function fail($m) { Write-Host "${R}✗ ERROR:${NC} $m"; Read-Host "Presiona Enter para cerrar"; exit 1 }
function step($m) { Write-Host "${B}→ $m${NC}" }

New-Item -ItemType Directory -Force $LOG | Out-Null

Write-Host ""
Write-Host "${G}${B}╔════════════════════════════════════════════╗${NC}"
Write-Host "${G}${B}║   CONCENTRADOS MONSERRATH v2.0             ║${NC}"
Write-Host "${G}${B}╚════════════════════════════════════════════╝${NC}"
Write-Host ""

# ── 1. Node.js ───────────────────────────────────────────────
step "Node.js..."
if (-not (Test-Path $NODE)) { fail "Node.js no encontrado en $NODE. Instala con: scoop install nodejs20" }
$nv = & $NODE --version 2>&1
ok "Node.js $nv"

# ── 2. .env ──────────────────────────────────────────────────
step "Configuración..."
$envFile = Join-Path $SERVER ".env"
if (-not (Test-Path $envFile)) { fail ".env no encontrado en $envFile" }
ok ".env OK"

# ── 3. npm install si falta ───────────────────────────────────
$expressPath = Join-Path $SERVER "node_modules\express"
if (-not (Test-Path $expressPath)) {
  step "Instalando dependencias npm..."
  & $NODE "$env:USERPROFILE\scoop\apps\nodejs20\current\npm" install --prefix $SERVER --production 2>&1 | Select-Object -Last 3
  ok "Dependencias instaladas"
}

# ── 4. Ollama (opcional) ─────────────────────────────────────
if (Test-Path $OLLAMA) {
  step "Ollama..."
  $running = Get-Process -Name ollama -ErrorAction SilentlyContinue
  if (-not $running) {
    Start-Process -FilePath $OLLAMA -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep -Seconds 2
  }
  ok "Ollama activo"
} else { warn "Ollama no instalado — parser usa modo reglas" }

# ── 5. Parar procesos previos ─────────────────────────────────
step "Limpiando procesos previos..."
Get-Process -Name node   -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name ngrok  -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
ok "Procesos anteriores detenidos"

# ── 6. Servidor Node.js ───────────────────────────────────────
step "Iniciando servidor..."
$logFile = Join-Path $LOG "server.log"
$env:BOT_ENABLED = (Get-Content $envFile | Select-String "BOT_ENABLED=true") ? "true" : "false"
$srv = Start-Process -FilePath $NODE -ArgumentList "$SERVER\src\index.js" `
  -WorkingDirectory $SERVER `
  -RedirectStandardOutput $logFile `
  -RedirectStandardError  (Join-Path $LOG "server.err") `
  -WindowStyle Hidden -PassThru

# Esperar hasta 25s
$srvOk = $false
for ($i = 0; $i -lt 25; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-RestMethod http://localhost:3000/health -TimeoutSec 1 -ErrorAction Stop
    if ($r.status -eq 'ok') { $srvOk = $true; break }
  } catch {}
}
if (-not $srvOk) {
  Get-Content $logFile -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
  fail "Servidor no respondió en 25s"
}
ok "Servidor activo (PID $($srv.Id))"

# Guardar PID para stop-windows.ps1
@{ server = $srv.Id } | ConvertTo-Json | Set-Content (Join-Path $PROJ ".pids.json")

# ── 7. ngrok ─────────────────────────────────────────────────
step "Iniciando ngrok..."
if (-not (Test-Path $NGROK)) { warn "ngrok no encontrado — acceso solo local"; goto :skepngrok }
$ngrokLog = Join-Path $LOG "ngrok.log"
$ngrokDomain = (Get-Content $envFile | Select-String "NGROK_DOMAIN=(.+)") ? $Matches[1].Trim() : ""
$ngrokArgs = if ($ngrokDomain) { "http 3000 --url=$ngrokDomain --log=stdout" } else { "http 3000 --log=stdout" }
$ngrok = Start-Process -FilePath $NGROK -ArgumentList $ngrokArgs `
  -RedirectStandardOutput $ngrokLog -WindowStyle Hidden -PassThru

# Esperar ngrok
$ngrokOk = $false
for ($i = 0; $i -lt 15; $i++) {
  Start-Sleep -Seconds 1
  try {
    $t = Invoke-RestMethod http://localhost:4040/api/tunnels -TimeoutSec 1 -ErrorAction Stop
    if ($t.tunnels.Count -gt 0) { $ngrokOk = $true; break }
  } catch {}
}

if ($ngrokOk) {
  $url = if ($ngrokDomain) { "https://$ngrokDomain" } else { (Invoke-RestMethod http://localhost:4040/api/tunnels).tunnels[0].public_url }
  ok "Túnel: $url"
  # Actualizar PID
  $pids = Get-Content (Join-Path $PROJ ".pids.json") | ConvertFrom-Json
  $pids | Add-Member -NotePropertyName ngrok -NotePropertyValue $ngrok.Id -Force
  $pids | ConvertTo-Json | Set-Content (Join-Path $PROJ ".pids.json")
} else { warn "ngrok no respondió — revisa $ngrokLog" }

# ── 8. Resumen ────────────────────────────────────────────────
$domain = if ($ngrokDomain) { $ngrokDomain } else { "localhost:3000" }
Write-Host ""
Write-Host "${G}${B}╔════════════════════════════════════════════╗${NC}"
Write-Host "${G}${B}║       SISTEMA ACTIVO Y FUNCIONANDO         ║${NC}"
Write-Host "${G}${B}╠════════════════════════════════════════════╣${NC}"
Write-Host "${G}${B}║${NC} App:    https://$($domain.PadRight(35)) ${G}${B}║${NC}"
Write-Host "${G}${B}║${NC} Logs:   $($LOG.Substring(0,[Math]::Min($LOG.Length,37)).PadRight(38)) ${G}${B}║${NC}"
Write-Host "${G}${B}║${NC} Parar:  .\stop-windows.ps1$((' ' * 22)) ${G}${B}║${NC}"
Write-Host "${G}${B}╚════════════════════════════════════════════╝${NC}"
Write-Host ""
Write-Host "  Presiona Ctrl+C para detener el monitoreo de logs"
Write-Host ""

# Monitor logs en tiempo real
Get-Content $logFile -Wait -Tail 0 | ForEach-Object { Write-Host "  [server] $_" }
