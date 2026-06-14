#Requires -Version 5.1
param(
    [string]$BotPhone = ''
)
<#
.SYNOPSIS
    Concentrados Monserrath v2.0 -- Instalacion y despliegue en Windows VPS
    Dominio : tu-dominio.duckdns.org | IP: 38.252.236.141
.NOTES
    Click derecho -> Ejecutar con PowerShell
    O desde cmd  : powershell -ExecutionPolicy Bypass -File deploy-windows.ps1
    Requiere     : Windows Server 2019+ o Windows 10+ con Apache ya instalado
#>

# -- Auto-elevacion a Administrador ---------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-NOT $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# -- Constantes pre-configuradas -------------------------------
$DOMAIN      = "tu-dominio.duckdns.org"
$DUCK_TOKEN  = "ec02d59d-b06c-4094-a4b1-0b5c1c95ce91"
$SUBDOMAIN   = "concentrados-monserrath"
$VPS_IP      = "38.252.236.141"
$PORT        = 3000
$SVC_NAME    = "MonserratNode"
$CF_SVC_NAME = "MonserratTunnel"

$PROJ        = "C:\Users\Administrator\Downloads\pedidos-whatsapp"
$LOG         = "C:\logs"
$ENV_FILE    = "$PROJ\server\.env"
$APPDATA_BOT = "C:\ProgramData\pedidos-bot"

# -- Helpers de consola ----------------------------------------
function Write-Ok($m)   { Write-Host "  [OK]  $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "  [!]   $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "  >>    $m" -ForegroundColor Cyan }
function Write-Die($m) {
    Write-Host ""
    Write-Host "  [ERROR] $m" -ForegroundColor Red
    Write-Host "  Log: $LOG\install.log" -ForegroundColor Yellow
    exit 1
}

# Refresca PATH desde el registro de Windows
function Update-Path {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH','User') + ';' +
                'C:\ProgramData\chocolatey\bin;C:\Program Files\nodejs;C:\Program Files\nssm'
}

# Ejecuta un comando externo capturando salida y codigo de salida
function Invoke-Cmd {
    param([string]$Exe, [string[]]$Args, [string]$Log = "$LOG\install.log")
    $out = & $Exe @Args 2>&1
    $out | Out-File $Log -Append -Encoding UTF8
    return $LASTEXITCODE
}

# Comprueba si un comando existe en PATH
function Test-Cmd($name) {
    return !!(Get-Command $name -ErrorAction SilentlyContinue)
}

# -------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host "   CONCENTRADOS MONSERRATH v2.0  --  Windows VPS" -ForegroundColor Green
Write-Host "   Dominio : $DOMAIN" -ForegroundColor Cyan
Write-Host "   IP      : $VPS_IP" -ForegroundColor Cyan
Write-Host "  ========================================================" -ForegroundColor Green
Write-Host ""

# Crear directorios de trabajo
foreach ($d in @($LOG, $PROJ, "$APPDATA_BOT\media", "$APPDATA_BOT\docs",
                  "$APPDATA_BOT\product-images", "$APPDATA_BOT\estados", "$APPDATA_BOT\auth")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
"" | Out-File "$LOG\install.log" -Encoding UTF8

# -------------------------------------------------------------
# PASO 0 -- Clonar / actualizar repositorio
# -------------------------------------------------------------
Write-Info "PASO 0 -- Descargando codigo fuente..."
$REPO_URL = "https://github.com/itanmidnight-ux/pedidos-whatsapp.git"
if (Test-Cmd 'git') {
    if (Test-Path "$PROJ\.git") {
        Write-Warn "Actualizando repositorio..."
        & git -C $PROJ pull --ff-only 2>&1 | Out-File "$LOG\install.log" -Append
    } else {
        Write-Warn "Clonando repositorio..."
        & git clone $REPO_URL $PROJ 2>&1 | Out-File "$LOG\install.log" -Append
    }
} else {
    Write-Warn "Git no instalado -- descargando ZIP..."
    $zipUrl = "https://github.com/itanmidnight-ux/pedidos-whatsapp/archive/refs/heads/main.zip"
    $zipTmp = "$env:TEMP\repo.zip"
    (New-Object Net.WebClient).DownloadFile($zipUrl, $zipTmp)
    Expand-Archive $zipTmp -DestinationPath "$env:TEMP\repo-extract" -Force
    Copy-Item "$env:TEMP\repo-extract\pedidos-whatsapp-main\*" $PROJ -Recurse -Force
    Remove-Item $zipTmp -Force
}
if (-not (Test-Path "$PROJ\server\package.json")) { Write-Die "Repositorio no descargado correctamente en $PROJ" }
Write-Ok "Codigo fuente OK en $PROJ"

# -------------------------------------------------------------
# PASO 1 -- Chocolatey
# -------------------------------------------------------------
Write-Info "PASO 1/10 -- Verificando Chocolatey..."
Update-Path
if (-not (Test-Cmd 'choco')) {
    Write-Warn "Instalando Chocolatey..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $choco_script = (New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
    Invoke-Expression $choco_script 2>&1 | Out-File "$LOG\install.log" -Append
    Update-Path
    if (-not (Test-Cmd 'choco')) { Write-Die "Chocolatey no se instalo. Revisa la conexion a Internet." }
    Write-Ok "Chocolatey instalado"
} else {
    Write-Ok "Chocolatey $(choco --version 2>$null)"
}

# -------------------------------------------------------------
# PASO 2 -- Node.js 20 LTS
# -------------------------------------------------------------
Write-Info "PASO 2/10 -- Verificando Node.js 20..."
Update-Path
$nodeVer = ''
try { $nodeVer = (& node --version 2>$null) } catch {}

if ($nodeVer -notmatch '^v20') {
    Write-Warn "Instalando Node.js 20 LTS..."
    $null = Invoke-Cmd 'choco' @('install','nodejs-lts','--version=20.18.0','-y','--no-progress')
    Update-Path
    try { $nodeVer = (& node --version 2>$null) } catch {}
    if ($nodeVer -notmatch '^v20') { Write-Die "Node.js 20 no se instalo. Intenta instalar manualmente desde nodejs.org" }
    # Configurar permanentemente en PATH del sistema
    $nodePath = (Get-Command node).Source | Split-Path
    $syspath  = [Environment]::GetEnvironmentVariable('PATH','Machine')
    if ($syspath -notlike "*$nodePath*") {
        [Environment]::SetEnvironmentVariable('PATH', "$syspath;$nodePath", 'Machine')
    }
    Write-Ok "Node.js $nodeVer instalado"
} else {
    Write-Ok "Node.js $nodeVer"
}

# -------------------------------------------------------------
# PASO 3 -- NSSM (Windows Service Manager para Node.js)
# -------------------------------------------------------------
Write-Info "PASO 3/10 -- Verificando NSSM (gestor de servicios)..."
$nssmExe = "$env:ProgramFiles\nssm\nssm.exe"
if (-not (Test-Path $nssmExe)) {
    Write-Warn "Instalando NSSM..."
    $null = Invoke-Cmd 'choco' @('install','nssm','-y','--no-progress','--force')
    Update-Path
    # Buscar nssm en paths posibles post-choco
    $nssmFound = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmFound) { $nssmExe = $nssmFound.Source }
    elseif (Test-Path "C:\ProgramData\chocolatey\bin\nssm.exe") { $nssmExe = "C:\ProgramData\chocolatey\bin\nssm.exe" }
    elseif (Test-Path "C:\ProgramData\chocolatey\lib\nssm\tools\nssm.exe") { $nssmExe = "C:\ProgramData\chocolatey\lib\nssm\tools\nssm.exe" }
    # Fallback: descarga directa si choco fallo
    if (-not (Test-Path $nssmExe)) {
        Write-Warn "Choco fallo -- descargando NSSM directamente..."
        $nssmDir  = "$env:ProgramFiles\nssm"
        New-Item -ItemType Directory -Force -Path $nssmDir | Out-Null
        $nssmZip  = "$env:TEMP\nssm.zip"
        (New-Object Net.WebClient).DownloadFile("https://nssm.cc/release/nssm-2.24.zip", $nssmZip)
        Expand-Archive $nssmZip -DestinationPath "$env:TEMP\nssm-extract" -Force
        Copy-Item "$env:TEMP\nssm-extract\nssm-2.24\win64\nssm.exe" "$nssmDir\nssm.exe" -Force
        $nssmExe = "$nssmDir\nssm.exe"
        $env:PATH += ";$nssmDir"
    }
    if (-not (Test-Path $nssmExe)) { Write-Die "NSSM no se instalo." }
    Write-Ok "NSSM instalado en $nssmExe"
} else {
    Write-Ok "NSSM OK ($nssmExe)"
}

# -------------------------------------------------------------
# PASO 4 -- Cloudflared (tunel de respaldo)
# -------------------------------------------------------------
Write-Info "PASO 4/10 -- Verificando cloudflared..."
Update-Path
$cfExe = ''
$cfDir = "$env:ProgramFiles\cloudflared"
$cfPaths = @(
    "$cfDir\cloudflared.exe",
    "C:\ProgramData\chocolatey\bin\cloudflared.exe",
    (Get-Command cloudflared -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)
foreach ($p in $cfPaths) {
    if ($p -and (Test-Path $p)) { $cfExe = $p; break }
}
if (-not $cfExe) {
    Write-Warn "Instalando cloudflared via descarga directa..."
    New-Item -ItemType Directory -Force -Path $cfDir | Out-Null
    $cfDest = "$cfDir\cloudflared.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        (New-Object Net.WebClient).DownloadFile(
            'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe',
            $cfDest)
        if (Test-Path $cfDest) { $cfExe = $cfDest; Write-Ok "cloudflared instalado en $cfDest" }
        else { Write-Warn "cloudflared descarga fallida" }
    } catch {
        Write-Warn "cloudflared error: $_"
    }
} else {
    Write-Ok "cloudflared OK ($cfExe)"
}

# PASO 5 -- HTTPS via cloudflared (reemplaza Certbot)
Write-Info "PASO 5/10 -- HTTPS: cloudflared maneja SSL (sin Certbot necesario)"
Write-Ok "SSL: cloudflared tunnel provee HTTPS automatico"

# -------------------------------------------------------------
# PASO 6 -- Dependencias npm
# -------------------------------------------------------------
Write-Info "PASO 6/10 -- Verificando dependencias npm..."
$nodeModules = "$PROJ\server\node_modules"
$pkgJson     = "$PROJ\server\package.json"
$pkgLock     = "$PROJ\server\package-lock.json"

# Solo instalar si node_modules no existe o package.json es mas nuevo
$needsInstall = $false
if (-not (Test-Path $nodeModules)) {
    $needsInstall = $true
} elseif ((Test-Path $pkgJson) -and (Test-Path "$nodeModules\.package-lock.json")) {
    $modTime = (Get-Item "$nodeModules\.package-lock.json").LastWriteTime
    $pkgTime = (Get-Item $pkgJson).LastWriteTime
    if ($pkgTime -gt $modTime) { $needsInstall = $true }
}

if ($needsInstall) {
    Write-Warn "Instalando dependencias npm..."
    Push-Location "$PROJ\server"
    $npmOut = npm install --production 2>&1
    $npmExit = $LASTEXITCODE
    $npmOut | Out-File "$LOG\npm.log" -Encoding UTF8
    Pop-Location
    if ($npmExit -ne 0) { Write-Die "npm install fallo (exit $npmExit). Revisa $LOG\npm.log" }
    Write-Ok "Dependencias npm instaladas"
} else {
    Write-Ok "Dependencias npm OK (cache)"
}

# -------------------------------------------------------------
# PASO 7 -- Archivo .env
# -------------------------------------------------------------
Write-Info "PASO 7/10 -- Configurando .env..."

if (-not (Test-Path $ENV_FILE)) {
    # Generar secretos criptograficos
    $rng = [Security.Cryptography.RNGCryptoServiceProvider]::new()
    $b32 = New-Object byte[] 32
    $rng.GetBytes($b32); $JWT = ($b32 | ForEach-Object { $_.ToString('x2') }) -join ''
    $rng.GetBytes($b32); $KEY = ($b32 | ForEach-Object { $_.ToString('x2') }) -join ''

    # BOT_PHONE vacio intencionalmente -- se configura al final de forma interactiva
    @"
PORT=$PORT
API_KEY=$KEY
JWT_SECRET=$JWT
BOT_ENABLED=true
BOT_PHONE=
SERVER_DOMAIN=$DOMAIN
DUCKDNS_TOKEN=$DUCK_TOKEN
"@ | Set-Content $ENV_FILE -Encoding UTF8
    Write-Ok ".env creado"
} else {
    # Actualizar/agregar claves que puedan faltar sin sobreescribir todo
    $envContent = Get-Content $ENV_FILE -Raw
    $updates = @{
        'SERVER_DOMAIN'  = $DOMAIN
        'DUCKDNS_TOKEN'  = $DUCK_TOKEN
    }
    foreach ($k in $updates.Keys) {
        if ($envContent -match "^$k=") {
            $envContent = $envContent -replace "(?m)^$k=.*", "$k=$($updates[$k])"
        } else {
            $envContent += "`r`n$k=$($updates[$k])"
        }
    }
    Set-Content $ENV_FILE $envContent -Encoding UTF8
    Write-Ok ".env verificado y actualizado"
}

# Cargar .env en proceso actual
Get-Content $ENV_FILE | ForEach-Object {
    if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), 'Process')
    }
}

# -------------------------------------------------------------
# PASO 8 -- DuckDNS + reglas de firewall + TCP optimizations
# -------------------------------------------------------------
Write-Info "PASO 8/10 -- Red: DuckDNS, firewall y TCP..."

# 8a. Actualizar IP en DuckDNS
Write-Info "  Actualizando DuckDNS..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $rc = $wc.DownloadString("https://www.duckdns.org/update?domains=$SUBDOMAIN&token=$DUCK_TOKEN&ip=").Trim()
    if ($rc -eq 'OK') { Write-Ok "DuckDNS actualizado -- $DOMAIN -> $VPS_IP" }
    else { Write-Warn "DuckDNS respondio: $rc" }
} catch { Write-Warn "DuckDNS: $_" }

# Script de actualizacion DuckDNS (se ejecutara como tarea programada)
$duckScript = "$PROJ\update-duckdns.ps1"
@"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    Invoke-WebRequest ``
        -Uri "https://www.duckdns.org/update?domains=$SUBDOMAIN&token=$DUCK_TOKEN&ip=" ``
        -UseBasicParsing -TimeoutSec 10 | Out-Null
} catch {}
"@ | Set-Content $duckScript -Encoding UTF8

# Registrar tarea DuckDNS (cada 10 min, inicio automatico con Windows)
Unregister-ScheduledTask -TaskName 'DuckDNS-Monserrath' -Confirm:$false -ErrorAction SilentlyContinue
$dnsAction   = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$duckScript`""
$dnsTrigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 10) `
    -RepetitionDuration (New-TimeSpan -Days 9999)
$dnsSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'DuckDNS-Monserrath' `
    -Action $dnsAction -Trigger $dnsTrigger -Settings $dnsSettings `
    -User 'NT AUTHORITY\SYSTEM' -RunLevel Highest -Force | Out-Null
Write-Ok "DuckDNS: tarea programada cada 10 minutos"

# 8b. Reglas de firewall (abrir puertos 80 y 443)
$fwRules = @(
    @{ Name='Monserrath-HTTP';  Port=80;   Protocol='TCP' },
    @{ Name='Monserrath-HTTPS'; Port=443;  Protocol='TCP' },
    @{ Name='Monserrath-Node';  Port=$PORT; Protocol='TCP' }
)
foreach ($rule in $fwRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound `
            -Protocol $rule.Protocol -LocalPort $rule.Port -Action Allow -Profile Any | Out-Null
        Write-Ok "Firewall: puerto $($rule.Port) abierto"
    }
}

# 8c. Optimizaciones TCP de Windows para conexiones rapidas y estables
netsh int tcp set global autotuninglevel=normal   2>$null | Out-Null
netsh int tcp set global chimney=disabled         2>$null | Out-Null
netsh int tcp set global rss=enabled              2>$null | Out-Null
netsh int tcp set global timestamps=disabled      2>$null | Out-Null
netsh int tcp set global initialRto=2000          2>$null | Out-Null
netsh int tcp set global maxsynretransmissions=2  2>$null | Out-Null
Write-Ok "TCP: parametros de rendimiento aplicados"

# -------------------------------------------------------------
# PASO 9 -- nginx: instalar + reverse proxy en puerto 80/443
# -------------------------------------------------------------
Write-Info "PASO 9/10 -- Configurando nginx reverse proxy..."

# Detectar nginx en rutas comunes
$nginxExe = $null
$nginxDir = $null
$nginxPaths = @('C:\nginx','C:\tools\nginx','C:\ProgramData\chocolatey\lib\nginx\tools\nginx')
foreach ($p in $nginxPaths) {
    if (Test-Path "$p\nginx.exe") { $nginxExe = "$p\nginx.exe"; $nginxDir = $p; break }
}

# Instalar nginx via choco si no existe
if (-not $nginxExe) {
    Write-Warn "nginx no encontrado -- instalando via Chocolatey..."
    $null = Invoke-Cmd 'choco' @('install','nginx','-y','--no-progress','--force')
    Update-Path
    Start-Sleep 5
    foreach ($p in $nginxPaths) {
        if (Test-Path "$p\nginx.exe") { $nginxExe = "$p\nginx.exe"; $nginxDir = $p; break }
    }
    $ngCmd = Get-Command nginx -ErrorAction SilentlyContinue
    if ($ngCmd -and -not $nginxExe) { $nginxExe = $ngCmd.Source; $nginxDir = Split-Path $nginxExe }
}

$nginxSvcName = 'MonserratNginx'
$nginxSvc     = Get-Service -Name $nginxSvcName -ErrorAction SilentlyContinue

if ($nginxExe -and (Test-Path $nginxExe)) {
    Write-Ok "nginx encontrado: $nginxExe"

    # Escribir config nginx
    $nginxConf = "$nginxDir\conf\nginx.conf"
    @"
worker_processes 1;
error_log $($LOG -replace '\\','/')/nginx-error.log warn;
pid       $($nginxDir -replace '\\','/')/logs/nginx.pid;

events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    client_max_body_size 50M;

    access_log $($LOG -replace '\\','/')/nginx-access.log;

    server {
        listen 80;
        server_name $DOMAIN $VPS_IP;

        location / {
            proxy_pass         http://127.0.0.1:$PORT;
            proxy_http_version 1.1;
            proxy_set_header   Upgrade `$http_upgrade;
            proxy_set_header   Connection 'upgrade';
            proxy_set_header   Host `$host;
            proxy_set_header   X-Real-IP `$remote_addr;
            proxy_set_header   X-Forwarded-For `$proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto `$scheme;
            proxy_cache_bypass `$http_upgrade;
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
        }
    }
}
"@ | Set-Content $nginxConf -Encoding UTF8
    Write-Ok "nginx: config escrita en $nginxConf"

    # Matar instancias previas de nginx
    Stop-Service $nginxSvcName -Force -ErrorAction SilentlyContinue
    & $nssmExe remove $nginxSvcName confirm 2>$null | Out-Null
    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2

    # Liberar puerto 80 si algo lo ocupa
    $p80 = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
    if ($p80) { Stop-Process -Id $p80[0].OwningProcess -Force -ErrorAction SilentlyContinue; Start-Sleep 1 }

    # Registrar nginx como servicio NSSM
    & $nssmExe install $nginxSvcName $nginxExe 2>$null | Out-Null
    & $nssmExe set $nginxSvcName AppDirectory $nginxDir 2>$null | Out-Null
    & $nssmExe set $nginxSvcName AppStdout "$LOG\nginx.log" 2>$null | Out-Null
    & $nssmExe set $nginxSvcName AppStderr "$LOG\nginx.log" 2>$null | Out-Null
    & $nssmExe set $nginxSvcName AppRestartDelay 5000 2>$null | Out-Null
    Set-Service -Name $nginxSvcName -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service $nginxSvcName -ErrorAction SilentlyContinue
    Start-Sleep 3
    $ngState = if ($s = Get-Service $nginxSvcName -ErrorAction SilentlyContinue) { $s.Status } else { 'Unknown' }
    if ($ngState -eq 'Running') { Write-Ok "nginx activo (puerto 80 -> localhost:$PORT)" }
    else { Write-Warn "nginx no arranco (estado: $ngState) -- usando portproxy como fallback" }
} else {
    Write-Warn "nginx no instalado -- usando netsh portproxy (80 -> $PORT)..."
}

# Fallback: netsh portproxy si nginx no esta disponible
$portproxy80 = netsh interface portproxy show v4tov4 2>$null | Select-String ":80\s"
if (-not ($nginxExe -and $nginxSvc) -or -not $portproxy80) {
    netsh interface portproxy delete v4tov4 listenport=80  listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=80  listenaddress=0.0.0.0 connectport=$PORT connectaddress=127.0.0.1 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=$PORT connectaddress=127.0.0.1 2>$null | Out-Null
    Write-Ok "Portproxy: 80/443 -> $PORT"
}

# Alias para compatibilidad con bloque de resumen
$apacheSvc = Get-Service -Name $nginxSvcName -ErrorAction SilentlyContinue


# -------------------------------------------------------------
# PASO 10 -- Servicio Windows para Node.js (via NSSM)
# -------------------------------------------------------------
Write-Info "PASO 10/10 -- Registrando Node.js como servicio de Windows..."

# Ruta absoluta al ejecutable de Node
$nodeExe = if ($c = Get-Command node -ErrorAction SilentlyContinue) { $c.Source } else { $null }
if (-not $nodeExe) {
    Update-Path
    $nodeExe = if ($c = Get-Command node -ErrorAction SilentlyContinue) { $c.Source } else { $null }
}
if (-not $nodeExe) { Write-Die "node.exe no encontrado en PATH. Reinstala Node.js." }
$serverScript = "$PROJ\server\src\index.js"
if (-not (Test-Path $serverScript)) { Write-Die "No se encontro $serverScript" }

# Cargar variables del .env para NSSM (cada par KEY=VALUE como argumento separado)
$envVars = @(Get-Content $ENV_FILE | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' })

# Limpiar sesion WhatsApp para forzar re-autenticacion
# El servicio corre como SYSTEM: APPDATA = C:\Windows\system32\config\systemprofile\AppData\Roaming
Write-Info "  Limpiando sesion WhatsApp para re-autenticacion..."
$authDirs = @(
    "$APPDATA_BOT\auth",
    "C:\Windows\system32\config\systemprofile\AppData\Roaming\pedidos-bot\auth",
    "C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\pedidos-bot\auth"
)
foreach ($aDir in $authDirs) {
    if (Test-Path $aDir) {
        Remove-Item $aDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Sesion borrada: $aDir"
    }
    New-Item -ItemType Directory -Force -Path $aDir | Out-Null
}
# Limpiar log para deteccion limpia de codigo de vinculacion
"" | Set-Content "$LOG\server.log" -Encoding UTF8

# Detener y eliminar servicio previo si existe
$existingSvc = Get-Service -Name $SVC_NAME -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Warn "Servicio $SVC_NAME existente -- actualizando..."
    Stop-Service  $SVC_NAME -Force -ErrorAction SilentlyContinue
    & $nssmExe remove $SVC_NAME confirm 2>$null | Out-Null
    Start-Sleep 2
}

# Liberar el puerto antes de arrancar
$portProc = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($portProc) {
    Stop-Process -Id $portProc[0].OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
}

# Instalar servicio con NSSM
& $nssmExe install $SVC_NAME $nodeExe $serverScript          2>$null | Out-Null
& $nssmExe set $SVC_NAME AppDirectory "$PROJ\server"         2>$null | Out-Null
& $nssmExe set $SVC_NAME AppStdout "$LOG\server.log"         2>$null | Out-Null
& $nssmExe set $SVC_NAME AppStderr "$LOG\server.log"         2>$null | Out-Null
& $nssmExe set $SVC_NAME AppStdoutCreationDisposition 4      2>$null | Out-Null
& $nssmExe set $SVC_NAME AppStderrCreationDisposition 4      2>$null | Out-Null
& $nssmExe set $SVC_NAME AppRotateFiles 1                    2>$null | Out-Null
& $nssmExe set $SVC_NAME AppRotateBytes 10485760             2>$null | Out-Null

# Variables de entorno del servicio -- cada KEY=VALUE como argumento separado
& $nssmExe set $SVC_NAME AppEnvironmentExtra @envVars 2>$null | Out-Null

# Configurar reinicio automatico en fallo
& $nssmExe set $SVC_NAME AppThrottle 5000                           2>$null | Out-Null
& $nssmExe set $SVC_NAME AppRestartDelay 5000                       2>$null | Out-Null
& $nssmExe set $SVC_NAME AppExit Default Restart                    2>$null | Out-Null

# Auto-inicio con Windows
Set-Service -Name $SVC_NAME -StartupType Automatic -ErrorAction SilentlyContinue
sc.exe failure $SVC_NAME reset=86400 actions=restart/5000/restart/10000/restart/30000 2>$null | Out-Null

Write-Ok "Servicio $SVC_NAME registrado con NSSM"

# Iniciar el servicio
Start-Service $SVC_NAME -ErrorAction SilentlyContinue
Start-Sleep 3
$svcStatus = if ($s = Get-Service $SVC_NAME -ErrorAction SilentlyContinue) { $s.Status } else { $null }
if ($svcStatus -ne 'Running') {
    Write-Warn "Reintentando inicio del servicio..."
    Start-Sleep 3
    Start-Service $SVC_NAME -ErrorAction SilentlyContinue
    Start-Sleep 3
    $svcStatus = if ($s = Get-Service $SVC_NAME -ErrorAction SilentlyContinue) { $s.Status } else { $null }
}

# Verificar que el servidor responde
$serverOk = $false
Write-Info "  Esperando que el servidor responda (max 45s)..."
for ($i = 0; $i -lt 45; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$PORT/health" `
            -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $serverOk = $true; break }
    } catch {}
    Start-Sleep 1
}

if (-not $serverOk) {
    Write-Host ""
    Write-Host "  Ultimas lineas del log:" -ForegroundColor Yellow
    Get-Content "$LOG\server.log" -Tail 25 -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    Write-Die "El servidor no respondio. Servicio ${SVC_NAME}: $svcStatus"
}
Write-Ok "Servicio $SVC_NAME activo en puerto $PORT (auto-inicio habilitado)"

# -- Cloudflared como tunel HTTPS publico (trycloudflare.com, sin cuenta) -----
if ($cfExe -and (Test-Path $cfExe)) {
    Write-Info "  Instalando cloudflared como tunel HTTPS publico..."
    Stop-Service $CF_SVC_NAME -Force -ErrorAction SilentlyContinue
    & $nssmExe remove $CF_SVC_NAME confirm 2>$null | Out-Null
    Start-Sleep 2
    # Apuntar al puerto de Apache (80) si Apache esta activo, sino directo a Node
    $tunnelPort = if ($apacheSvc -and $apacheSvc.Status -eq 'Running') { 80 } else { $PORT }
    & $nssmExe install $CF_SVC_NAME $cfExe "tunnel --url http://localhost:$tunnelPort --no-autoupdate" 2>$null | Out-Null
    & $nssmExe set $CF_SVC_NAME AppStdout "$LOG\tunnel.log" 2>$null | Out-Null
    & $nssmExe set $CF_SVC_NAME AppStderr "$LOG\tunnel.log" 2>$null | Out-Null
    & $nssmExe set $CF_SVC_NAME AppStdoutCreationDisposition 2 2>$null | Out-Null
    & $nssmExe set $CF_SVC_NAME AppStderrCreationDisposition 2 2>$null | Out-Null
    & $nssmExe set $CF_SVC_NAME AppRestartDelay 10000 2>$null | Out-Null
    Set-Service -Name $CF_SVC_NAME -StartupType Automatic -ErrorAction SilentlyContinue
    "" | Set-Content "$LOG\tunnel.log" -Encoding UTF8
    Start-Service $CF_SVC_NAME -ErrorAction SilentlyContinue
    # Esperar URL del tunel (max 30s)
    $tunnelUrl = ''
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep 2
        $tlog = Get-Content "$LOG\tunnel.log" -Raw -ErrorAction SilentlyContinue
        if ($tlog -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $Matches[0]; break
        }
    }
    if ($tunnelUrl) {
        Write-Ok "Cloudflare tunnel activo: $tunnelUrl"
    } else {
        Write-Ok "Servicio $CF_SVC_NAME registrado (URL aparece en $LOG\tunnel.log)"
    }
} else {
    Write-Warn "cloudflared no disponible -- acceso via DuckDNS: http://$DOMAIN"
    $tunnelUrl = ''
}

# -- Configuracion interactiva de WhatsApp ---------------------
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host "  |   CONFIGURACION WHATSAPP -- Numero de telefono      |" -ForegroundColor Cyan
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host ""

$BOT_PHONE = ($BotPhone -replace '\D','')
if ($BOT_PHONE.Length -lt 10) {
    Write-Host "  Ingresa el numero de telefono que vincularas a WhatsApp." -ForegroundColor White
    Write-Host "  Incluye codigo de pais sin + ni espacios." -ForegroundColor Gray
    Write-Host "  Ejemplo Colombia: 573044016277" -ForegroundColor Gray
    Write-Host ""
    do {
        $BOT_PHONE = (Read-Host "  Numero de telefono") -replace '\D',''
        if ($BOT_PHONE.Length -lt 10) {
            Write-Warn "Numero invalido. Debe tener minimo 10 digitos. Intenta de nuevo."
        }
    } while ($BOT_PHONE.Length -lt 10)
}

Write-Ok "Numero aceptado: $BOT_PHONE"

# Actualizar BOT_PHONE en .env
$envContent = Get-Content $ENV_FILE -Raw -ErrorAction SilentlyContinue
if ($envContent -match '(?m)^BOT_PHONE=') {
    $envContent = $envContent -replace '(?m)^BOT_PHONE=.*', "BOT_PHONE=$BOT_PHONE"
} else {
    $envContent = $envContent.TrimEnd() + "`r`nBOT_PHONE=$BOT_PHONE`r`n"
}
Set-Content $ENV_FILE $envContent -Encoding UTF8
Write-Ok ".env actualizado con BOT_PHONE=$BOT_PHONE"

# Limpiar sesion WhatsApp y log antes de reiniciar
Write-Info "Limpiando sesion WhatsApp..."
$authDirsWa = @(
    "$APPDATA_BOT\auth",
    "C:\Windows\system32\config\systemprofile\AppData\Roaming\pedidos-bot\auth",
    "C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\pedidos-bot\auth"
)
foreach ($aDir in $authDirsWa) {
    Remove-Item $aDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $aDir | Out-Null
}
"" | Set-Content "$LOG\server.log" -Encoding UTF8

# Reiniciar servicio para aplicar nuevo BOT_PHONE
Write-Info "Reiniciando servicio con numero $BOT_PHONE..."
Stop-Service $SVC_NAME -Force -ErrorAction SilentlyContinue
Start-Sleep 4
Start-Service $SVC_NAME -ErrorAction SilentlyContinue

# Esperar a que el servidor responda
Write-Info "Esperando que el servidor arranque (max 30s)..."
for ($i = 0; $i -lt 30; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:$PORT/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { break }
    } catch {}
    Start-Sleep 1
}

# Esperar codigo de vinculacion WhatsApp -- loop infinito hasta conectar
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host "  |   VINCULACION WHATSAPP -- Sin limite de tiempo       |" -ForegroundColor Cyan
Write-Host "  |   Cada codigo dura ~60s. Se mostrara uno nuevo       |" -ForegroundColor Cyan
Write-Host "  |   automaticamente si el anterior expira.             |" -ForegroundColor Cyan
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Info "Esperando primer codigo de vinculacion..."
Write-Host ""

$lastShownCode = ''
$connected     = $false
$dotCount      = 0

while ($true) {
    $logContent = Get-Content "$LOG\server.log" -Raw -ErrorAction SilentlyContinue

    if ($logContent -cmatch '\[bot\].*Connected') {
        Write-Host ""
        Write-Host ""
        Write-Ok "!!! Bot WhatsApp CONECTADO exitosamente !!!"
        $connected = $true
        break
    }

    $allM = [regex]::Matches($logContent, 'Pairing code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})')
    if ($allM.Count -gt 0) {
        $latestCode = $allM[$allM.Count - 1].Groups[1].Value
        if ($latestCode -ne $lastShownCode) {
            $lastShownCode = $latestCode
            $dotCount      = 0
            Write-Host ""
            Write-Host "  +=========================================+" -ForegroundColor Green
            Write-Host "  |    CODIGO DE VINCULACION WHATSAPP       |" -ForegroundColor Green
            Write-Host "  |                                         |" -ForegroundColor Green
            Write-Host "  |         >>> $latestCode <<<             |" -ForegroundColor Yellow
            Write-Host "  |                                         |" -ForegroundColor Green
            Write-Host "  |  1. Abre WhatsApp en tu telefono        |" -ForegroundColor White
            Write-Host "  |  2. Menu (3 puntos) > Dispositivos      |" -ForegroundColor White
            Write-Host "  |  3. Vincular un dispositivo             |" -ForegroundColor White
            Write-Host "  |  4. Vincular con numero de telefono     |" -ForegroundColor White
            Write-Host "  |  5. Ingresa el codigo de arriba         |" -ForegroundColor White
            Write-Host "  |                                         |" -ForegroundColor Green
            Write-Host "  |  Tienes ~60 segundos para ingresarlo.   |" -ForegroundColor Yellow
            Write-Host "  |  Si expira, un nuevo codigo aparecer    |" -ForegroundColor Yellow
            Write-Host "  |  automaticamente abajo.                 |" -ForegroundColor Yellow
            Write-Host "  +=========================================+" -ForegroundColor Green
            Write-Host ""
            Write-Info "Esperando confirmacion de WhatsApp..."
        }
    }

    Write-Host "  . " -NoNewline -ForegroundColor DarkGray
    $dotCount++
    Start-Sleep 3
}

# -- Resumen ---------------------------------------------------
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |        SISTEMA ACTIVO Y FUNCIONANDO                  |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  | DuckDNS: http://$DOMAIN  |" -ForegroundColor White
if ($tunnelUrl) {
    Write-Host "  | Tunnel : $tunnelUrl" -ForegroundColor Green
    Write-Host "  |   App  : $tunnelUrl/app/" -ForegroundColor Green
    Write-Host "  |   API  : $tunnelUrl/api/" -ForegroundColor Green
}
Write-Host "  | Local  : http://localhost:$PORT                |" -ForegroundColor Cyan
Write-Host "  +------------------------------------------------------+" -ForegroundColor Green
Write-Host "  | Logs          : $LOG\            |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  Servicios activos (sobreviven reinicios):" -ForegroundColor Yellow
Write-Host "    - $SVC_NAME  (Node.js, NSSM)"            -ForegroundColor Yellow
Write-Host "    - $CF_SVC_NAME  (cloudflared tunnel)"     -ForegroundColor Yellow
if ($apacheSvc) { Write-Host "    - $($apacheSvc.Name)  (nginx reverse proxy, puerto 80)" -ForegroundColor Yellow }
Write-Host "    - DuckDNS-Monserrath  (tarea programada cada 10 min)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Deploy completado." -ForegroundColor Green
