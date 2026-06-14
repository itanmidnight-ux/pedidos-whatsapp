#Requires -Version 5.1
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

$PROJ     = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOG      = "$PROJ\logs"
$ENV_FILE = "$PROJ\server\.env"
$APPDATA_BOT = "$env:APPDATA\pedidos-bot"

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
foreach ($d in @($LOG, "$APPDATA_BOT\media", "$APPDATA_BOT\docs",
                  "$APPDATA_BOT\product-images", "$APPDATA_BOT\estados", "$APPDATA_BOT\auth")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
"" | Out-File "$LOG\install.log" -Encoding UTF8

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
$cfPaths = @(
    "$env:ProgramFiles\cloudflared\cloudflared.exe",
    "C:\ProgramData\chocolatey\bin\cloudflared.exe",
    (Get-Command cloudflared -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)
foreach ($p in $cfPaths) {
    if ($p -and (Test-Path $p)) { $cfExe = $p; break }
}
if (-not $cfExe) {
    Write-Warn "Instalando cloudflared..."
    $null = Invoke-Cmd 'choco' @('install','cloudflared','-y','--no-progress')
    Update-Path
    foreach ($p in $cfPaths) {
        if ($p -and (Test-Path $p)) { $cfExe = $p; break }
    }
    $cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cfCmd) { $cfExe = $cfCmd.Source }
    if (-not $cfExe) { Write-Warn "cloudflared no encontrado -- continuando sin tunel de respaldo" }
    else { Write-Ok "cloudflared instalado" }
} else {
    Write-Ok "cloudflared OK"
}

# -------------------------------------------------------------
# PASO 5 -- Certbot (SSL / Let's Encrypt)
# -------------------------------------------------------------
Write-Info "PASO 5/10 -- Verificando Certbot (SSL)..."
$certbotExe = ''
$certbotPaths = @(
    "$env:ProgramFiles\Certbot\bin\certbot.exe",
    "C:\ProgramData\chocolatey\bin\certbot.exe",
    (Get-Command certbot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)
foreach ($p in $certbotPaths) {
    if ($p -and (Test-Path $p)) { $certbotExe = $p; break }
}
if (-not $certbotExe) {
    Write-Warn "Instalando Certbot..."
    $null = Invoke-Cmd 'choco' @('install','certbot','-y','--no-progress')
    Update-Path
    foreach ($p in $certbotPaths) {
        if ($p -and (Test-Path $p)) { $certbotExe = $p; break }
    }
    $cbCmd = Get-Command certbot -ErrorAction SilentlyContinue
    if ($cbCmd) { $certbotExe = $cbCmd.Source }
    if ($certbotExe) { Write-Ok "Certbot instalado" }
    else { Write-Warn "Certbot no encontrado -- se configurara SSL manualmente" }
} else {
    Write-Ok "Certbot OK"
}

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
    Write-Host ""
    Write-Host "  Primera ejecucion -- configuracion inicial" -ForegroundColor Yellow
    Write-Host ""
    $BOT_PHONE = ($env:BOT_PHONE -replace '\D','')
    if ($BOT_PHONE.Length -lt 10) { $BOT_PHONE = '573044016277' }

    # Generar secretos criptograficos
    $rng = [Security.Cryptography.RNGCryptoServiceProvider]::new()
    $b32 = New-Object byte[] 32
    $rng.GetBytes($b32); $JWT = ($b32 | ForEach-Object { $_.ToString('x2') }) -join ''
    $rng.GetBytes($b32); $KEY = ($b32 | ForEach-Object { $_.ToString('x2') }) -join ''

    @"
PORT=$PORT
API_KEY=$KEY
JWT_SECRET=$JWT
BOT_ENABLED=true
BOT_PHONE=$BOT_PHONE
SERVER_DOMAIN=$DOMAIN
DUCKDNS_TOKEN=$DUCK_TOKEN
NGROK_AUTHTOKEN=34G7biMjp4tdGcupxvySfJvYqrQ_6BEU8VntbCjSudDRWntdB
NGROK_DOMAIN=francoise-subhumid-maire.ngrok-free.dev
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
    $r = Invoke-WebRequest `
        -Uri "https://www.duckdns.org/update?domains=$SUBDOMAIN&token=$DUCK_TOKEN&ip=" `
        -UseBasicParsing -TimeoutSec 15
    if ($r.Content.Trim() -eq 'OK') { Write-Ok "DuckDNS actualizado -- $DOMAIN -> $VPS_IP" }
    else { Write-Warn "DuckDNS respondio: $($r.Content.Trim())" }
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
$dnsTrigger  = New-ScheduledTaskTrigger -Once -At (Get-Date)
$dnsTrigger.Repetition.Interval = 'PT10M'
$dnsTrigger.Repetition.Duration = 'P9999D'
$dnsSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'DuckDNS-Monserrath' `
    -Action $dnsAction -Trigger $dnsTrigger -Settings $dnsSettings `
    -RunLevel Highest -Force | Out-Null
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
# PASO 9 -- Apache: reverse proxy + SSL
# -------------------------------------------------------------
Write-Info "PASO 9/10 -- Configurando Apache..."

# Buscar Apache en rutas comunes
$apacheConfDir = $null
$apachePatterns = @(
    'C:\Apache24\conf',
    'C:\Apache2\conf',
    'C:\Apache2.4\conf',
    'C:\xampp\apache\conf',
    'C:\wamp64\bin\apache\apache2.4.*\conf',
    'C:\wamp\bin\apache\apache2.4.*\conf',
    'C:\laragon\bin\apache\apache-*\conf'
)
foreach ($pat in $apachePatterns) {
    $res = Resolve-Path $pat -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($res -and (Test-Path "$($res.Path)\httpd.conf")) {
        $apacheConfDir = $res.Path
        break
    }
}

$apacheSvc = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^Apache|^httpd' -or $_.DisplayName -match 'Apache HTTP' } |
    Select-Object -First 1

if ($apacheConfDir) {
    Write-Ok "Apache encontrado: $apacheConfDir"
    $httpdConf  = "$apacheConfDir\httpd.conf"
    $extraDir   = "$apacheConfDir\extra"
    New-Item -ItemType Directory -Force -Path $extraDir | Out-Null

    # Habilitar modulos necesarios (quitar # de LoadModule)
    $conf = Get-Content $httpdConf -Raw -Encoding UTF8
    @('proxy_module','proxy_http_module','proxy_wstunnel_module',
      'headers_module','rewrite_module','ssl_module') | ForEach-Object {
        $conf = $conf -replace ('#\s*LoadModule ' + $_ + '\b'), "LoadModule $_"
    }
    $conf = $conf -replace '#(Include conf/extra/httpd-ssl\.conf)',    '$1'
    $conf = $conf -replace '#(Include conf/extra/httpd-vhosts\.conf)', '$1'
    Set-Content $httpdConf $conf -Encoding UTF8

    # Obtener certificado SSL si no existe
    $certFile = "C:\Certbot\live\$DOMAIN\fullchain.pem"
    $keyFile  = "C:\Certbot\live\$DOMAIN\privkey.pem"
    $sslOk    = Test-Path $certFile

    if (-not $sslOk -and $certbotExe -and (Test-Path $certbotExe)) {
        Write-Info "  Obteniendo certificado SSL (Let's Encrypt)..."
        Write-Info "  Deteniendo Apache para challenge HTTP..."
        if ($apacheSvc) { Stop-Service $apacheSvc.Name -Force -ErrorAction SilentlyContinue }
        Start-Sleep 3

        # Liberar puerto 80 si lo tiene algo mas
        $p80 = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue
        if ($p80) { Stop-Process -Id $p80[0].OwningProcess -Force -ErrorAction SilentlyContinue }

        $p = Start-Process -FilePath $certbotExe `
            -ArgumentList "certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email webmaster@$DOMAIN --preferred-challenges http" `
            -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0 -and (Test-Path $certFile)) {
            Write-Ok "Certificado SSL obtenido para $DOMAIN"
            $sslOk = $true
        } else {
            Write-Warn "Certbot fallo (exit $($p.ExitCode))"
            Write-Warn "Asegurate de que el puerto 80 sea accesible desde Internet"
            Write-Warn "Vuelve a ejecutar este script cuando el puerto este abierto"
        }
    }

    # Generar vhost Apache (HTTPS si hay cert, HTTP temporal si no)
    $vhostFile = "$extraDir\monserrath-vhost.conf"
    if ($sslOk) {
        @"
# ===================================================
#  Concentrados Monserrath - Apache VirtualHost HTTPS
#  Generado por deploy-windows.ps1
# ===================================================

# Puerto 80 -> redirigir a HTTPS
<VirtualHost *:80>
    ServerName $DOMAIN
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>

# Puerto 443 - Reverse Proxy HTTPS
<VirtualHost *:443>
    ServerName $DOMAIN

    SSLEngine               on
    SSLCertificateFile      "C:/Certbot/live/$DOMAIN/cert.pem"
    SSLCertificateKeyFile   "C:/Certbot/live/$DOMAIN/privkey.pem"
    SSLCertificateChainFile "C:/Certbot/live/$DOMAIN/chain.pem"
    SSLProtocol             all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite          HIGH:!aNULL:!MD5

    # Proxy a Node.js
    ProxyPreserveHost On
    ProxyRequests     Off

    # WebSocket y SSE
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteRule ^/(.*) ws://127.0.0.1:$PORT/`$1 [P,L]

    ProxyPass        / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/

    Header always set X-Forwarded-Proto "https"
    Header always set X-Real-IP "%{REMOTE_ADDR}e"
    RequestHeader set ngrok-skip-browser-warning "true"

    # Keep-Alive para conexiones rapidas
    KeepAlive On
    KeepAliveTimeout 65
    MaxKeepAliveRequests 100

    ErrorLog  "$LOG/apache-error.log"
    CustomLog "$LOG/apache-access.log" combined
</VirtualHost>
"@ | Set-Content $vhostFile -Encoding UTF8
        Write-Ok "Apache: vhost HTTPS configurado"
    } else {
        @"
# ===================================================
#  Concentrados Monserrath - Apache VirtualHost HTTP
#  TEMPORAL - volver a ejecutar para obtener SSL
# ===================================================
<VirtualHost *:80>
    ServerName $DOMAIN

    ProxyPreserveHost On
    ProxyRequests     Off
    ProxyPass         / http://127.0.0.1:$PORT/
    ProxyPassReverse  / http://127.0.0.1:$PORT/

    RequestHeader set ngrok-skip-browser-warning "true"
    KeepAlive On
    KeepAliveTimeout 65

    ErrorLog  "$LOG/apache-error.log"
    CustomLog "$LOG/apache-access.log" combined
</VirtualHost>
"@ | Set-Content $vhostFile -Encoding UTF8
        Write-Ok "Apache: vhost HTTP (temporal -- sin SSL aun)"
    }

    # Incluir vhost en httpd.conf si no esta
    $confCheck = Get-Content $httpdConf -Raw -Encoding UTF8
    if ($confCheck -notmatch 'monserrath-vhost\.conf') {
        Add-Content $httpdConf "`r`nInclude conf/extra/monserrath-vhost.conf" -Encoding UTF8
        Write-Ok "Apache: include de vhost agregado a httpd.conf"
    }

    # Tarea de renovacion SSL (diaria a las 3am)
    if ($sslOk -and $certbotExe -and (Test-Path $certbotExe)) {
        Unregister-ScheduledTask -TaskName 'Certbot-Renew' -Confirm:$false -ErrorAction SilentlyContinue
        $apacheSvcName = if ($apacheSvc) { $apacheSvc.Name } else { 'Apache24' }
        $renewAction   = New-ScheduledTaskAction -Execute $certbotExe `
            -Argument "renew --quiet --deploy-hook `"net start $apacheSvcName`""
        $renewTrigger  = New-ScheduledTaskTrigger -Daily -At '03:00'
        $renewSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable
        Register-ScheduledTask -TaskName 'Certbot-Renew' `
            -Action $renewAction -Trigger $renewTrigger -Settings $renewSettings `
            -RunLevel Highest -Force | Out-Null
        Write-Ok "SSL: renovacion automatica programada (3am diario)"
    }

    # Reiniciar Apache como servicio
    if ($apacheSvc) {
        Restart-Service $apacheSvc.Name -ErrorAction SilentlyContinue
        Start-Sleep 2
        $svcState = if ($s = Get-Service $apacheSvc.Name -ErrorAction SilentlyContinue) { $s.Status } else { $null }
        if ($svcState -eq 'Running') { Write-Ok "Apache: servicio activo" }
        else { Write-Warn "Apache: el servicio no arranco. Revisa la config manualmente." }
    }
} else {
    Write-Warn "Apache no encontrado en rutas conocidas"
    Write-Warn "Instala Apache24 desde https://www.apachelounge.com/download/"
    Write-Warn "El servidor sera accesible directamente en http://${VPS_IP}:${PORT}"
}

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

# -- Cloudflared como servicio de respaldo (si no hay Apache o no hay SSL) -----
if ($cfExe -and (Test-Path $cfExe)) {
    $cfSvcExists = Get-Service -Name $CF_SVC_NAME -ErrorAction SilentlyContinue
    # Solo instalar tunel si Apache no tiene SSL
    $needsTunnel = -not ($apacheConfDir -and (Test-Path "C:\Certbot\live\$DOMAIN\fullchain.pem"))
    if ($needsTunnel -and -not $cfSvcExists) {
        Write-Info "  Instalando cloudflared como servicio de respaldo..."
        Stop-Service $CF_SVC_NAME -Force -ErrorAction SilentlyContinue
        & $nssmExe remove $CF_SVC_NAME confirm 2>$null | Out-Null
        & $nssmExe install $CF_SVC_NAME $cfExe "tunnel --url http://localhost:$PORT --no-autoupdate" 2>$null | Out-Null
        & $nssmExe set $CF_SVC_NAME AppStdout "$LOG\tunnel.log" 2>$null | Out-Null
        & $nssmExe set $CF_SVC_NAME AppStderr "$LOG\tunnel.log" 2>$null | Out-Null
        & $nssmExe set $CF_SVC_NAME AppRestartDelay 10000 2>$null | Out-Null
        Set-Service -Name $CF_SVC_NAME -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service $CF_SVC_NAME -ErrorAction SilentlyContinue
        Start-Sleep 5
        # Extraer URL del tunel del log
        $tunnelUrl = ''
        $tlog = Get-Content "$LOG\tunnel.log" -Raw -ErrorAction SilentlyContinue
        if ($tlog -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $tunnelUrl = $Matches[0]
            Write-Ok "Tunel cloudflare activo: $tunnelUrl"
        } else {
            Write-Ok "Servicio $CF_SVC_NAME registrado (tunel de respaldo)"
        }
    } elseif ($needsTunnel) {
        Write-Ok "Servicio $CF_SVC_NAME ya existe"
    }
}

# -- Codigo de vinculacion WhatsApp ----------------------------
Write-Host ""
Write-Info "Esperando codigo de vinculacion WhatsApp (max 80s)..."
$pairCode  = ''
$connected = $false
for ($i = 0; $i -lt 40; $i++) {
    $logContent = Get-Content "$LOG\server.log" -Raw -ErrorAction SilentlyContinue
    if ($logContent -match '\[bot\].*nect') { $connected = $true; break }
    if ($logContent -match '([A-Z0-9]{4}-[A-Z0-9]{4})') { $pairCode = $Matches[1]; break }
    Start-Sleep 2
}

Write-Host ""
if ($connected) {
    Write-Ok "Bot WhatsApp ya conectado (sesion existente)"
} elseif ($pairCode) {
    Write-Host "  +----------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |     CODIGO DE VINCULACION WHATSAPP                 |" -ForegroundColor Green
    Write-Host "  |----------------------------------------------------|" -ForegroundColor Green
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  |           $pairCode                           |" -ForegroundColor White
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  |  1. Abre WhatsApp en tu telefono                   |" -ForegroundColor Green
    Write-Host "  |  2. Menu (3 puntos) > Dispositivos vinculados      |" -ForegroundColor Green
    Write-Host "  |  3. Vincular dispositivo > Vincular con numero     |" -ForegroundColor Green
    Write-Host "  |  4. Ingresa el codigo de arriba                    |" -ForegroundColor Green
    Write-Host "  +----------------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Info "Esperando confirmacion (max 120s)..."
    for ($i = 0; $i -lt 60; $i++) {
        $lc = Get-Content "$LOG\server.log" -Raw -ErrorAction SilentlyContinue
        if ($lc -match '\[bot\].*nect') { Write-Ok "Bot WhatsApp CONECTADO!"; break }
        Start-Sleep 2
    }
} else {
    Write-Warn "Codigo de vinculacion no aparecio en 80s"
    Write-Warn "Revisa BOT_PHONE en $ENV_FILE y: Get-Content $LOG\server.log -Tail 30"
}

# -- Resumen ---------------------------------------------------
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |        SISTEMA ACTIVO Y FUNCIONANDO                  |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  | App    : https://$DOMAIN/app/  |" -ForegroundColor White
Write-Host "  | API    : https://$DOMAIN/api/  |" -ForegroundColor White
Write-Host "  | Health : https://$DOMAIN/health|" -ForegroundColor White
Write-Host "  | Local  : http://localhost:$PORT                |" -ForegroundColor Cyan
Write-Host "  +------------------------------------------------------+" -ForegroundColor Green
Write-Host "  | Servicio Node : sc query $SVC_NAME             |" -ForegroundColor Green
Write-Host "  | Logs          : $LOG\            |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  Servicios instalados como Windows Services (sobreviven reinicios):" -ForegroundColor Yellow
Write-Host "    - $SVC_NAME  (Node.js server, NSSM)"    -ForegroundColor Yellow
if ($apacheSvc) { Write-Host "    - $($apacheSvc.Name)  (Apache reverse proxy)" -ForegroundColor Yellow }
Write-Host "    - DuckDNS-Monserrath  (tarea programada cada 10 min)"           -ForegroundColor Yellow
Write-Host ""
Write-Host "  IMPORTANTE -- Verifica que estos puertos esten abiertos en el VPS:" -ForegroundColor Cyan
Write-Host "    Puerto 80  (HTTP / Let's Encrypt challenge)"                     -ForegroundColor Cyan
Write-Host "    Puerto 443 (HTTPS)"                                              -ForegroundColor Cyan
Write-Host ""
Read-Host "  Presiona Enter para cerrar"
