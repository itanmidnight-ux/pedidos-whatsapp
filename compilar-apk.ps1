#Requires -Version 5.1
# ================================================================
#  compilar-apk.ps1 — Compila APK de Concentrados Monserrath
#  Instala automáticamente: Java 17, Android SDK, Flutter
#  Uso: .\compilar-apk.ps1
# ================================================================

param([switch]$Clean)

$ErrorActionPreference = 'Stop'
$PROJ   = Split-Path $MyInvocation.MyCommand.Path
$APPDIR = Join-Path $PROJ "android-app"
$SDK    = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$OUT    = Join-Path $PROJ "app-release.apk"

$GREEN = "`e[32m"; $YELLOW = "`e[33m"; $RED = "`e[31m"; $NC = "`e[0m"; $BOLD = "`e[1m"
function ok($m)   { Write-Host "${GREEN}✓${NC} $m" }
function warn($m) { Write-Host "${YELLOW}⚠${NC}  $m" }
function step($m) { Write-Host "${BOLD}→ $m${NC}" }
function fail($m) { Write-Host "${RED}✗ ERROR:${NC} $m"; exit 1 }

# Refresh PATH helper
function RefreshPath {
    $paths = @(
        "$env:USERPROFILE\scoop\shims",
        "$env:USERPROFILE\scoop\apps\flutter\current\bin",
        (Get-Command java -ErrorAction SilentlyContinue)?.Source | Split-Path
    ) | Where-Object { $_ -and (Test-Path $_) }
    $env:PATH = ($paths + ($env:PATH -split ';') | Select-Object -Unique) -join ';'
}

Write-Host ""
Write-Host "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
Write-Host "${GREEN}${BOLD}║  Compilador APK - Concentrados Monserrath  ║${NC}"
Write-Host "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
Write-Host ""

# ── 1. Java 17 ───────────────────────────────────────────────
step "Verificando Java 17..."
$javaOk = $false
try {
    $jv = & java -version 2>&1 | Select-String "version"
    if ($jv -match '"17\.|"21\.|"22\.|"23\.|"24\.') { $javaOk = $true }
} catch {}

if (-not $javaOk) {
    warn "Java 17 no encontrado. Instalando via Scoop..."
    $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
    try {
        & "$env:USERPROFILE\scoop\shims\scoop.cmd" bucket add extras 2>$null
        & "$env:USERPROFILE\scoop\shims\scoop.cmd" install temurin17-jdk 2>&1 | Select-Object -Last 3
    } catch {
        warn "Scoop falló, intentando winget..."
        & winget install EclipseAdoptium.Temurin.17.JDK -e --silent 2>&1 | Select-Object -Last 2
    }
    RefreshPath
    try { $jv2 = & java -version 2>&1; ok "Java instalado: $($jv2 | Select-String 'version')" }
    catch { fail "Java 17 no pudo instalarse. Instala manualmente desde https://adoptium.net" }
} else {
    ok "Java: $($jv -replace '.*version "([^"]+)".*','$1')"
}

# Configurar JAVA_HOME
$javaExe = (Get-Command java -ErrorAction SilentlyContinue)?.Source
if ($javaExe) {
    $env:JAVA_HOME = (Split-Path (Split-Path $javaExe))
    ok "JAVA_HOME = $env:JAVA_HOME"
} else { fail "No se encontró java en PATH. Reinicia PowerShell e intenta de nuevo." }

# ── 2. Flutter ───────────────────────────────────────────────
step "Verificando Flutter..."
$env:PATH = "$env:USERPROFILE\scoop\shims;$env:USERPROFILE\scoop\apps\flutter\current\bin;$env:PATH"
try {
    $fv = & flutter --version 2>&1 | Select-String "Flutter"
    ok "Flutter: $($fv -replace 'Flutter (\S+).*','$1')"
} catch {
    warn "Flutter no encontrado. Instalando via Scoop..."
    & "$env:USERPROFILE\scoop\shims\scoop.cmd" bucket add extras 2>$null
    & "$env:USERPROFILE\scoop\shims\scoop.cmd" install flutter 2>&1 | Select-Object -Last 3
    $env:PATH = "$env:USERPROFILE\scoop\apps\flutter\current\bin;$env:PATH"
    try { $fv2 = & flutter --version 2>&1 | Select-String "Flutter"; ok "Flutter instalado: $fv2" }
    catch { fail "Flutter no pudo instalarse." }
}

# ── 3. Android SDK ───────────────────────────────────────────
step "Verificando Android SDK..."
$env:ANDROID_HOME    = $SDK
$env:ANDROID_SDK_ROOT = $SDK
$env:PATH = "$SDK\cmdline-tools\latest\bin;$SDK\platform-tools;$SDK\build-tools\34.0.0;$env:PATH"

$sdkManager = Join-Path $SDK "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    warn "Android SDK no encontrado. Descargando cmdline-tools..."

    $tmpZip = Join-Path $env:TEMP "cmdline-tools.zip"
    $tmpDir = Join-Path $env:TEMP "cmdline-tools-extract"

    # Descargar cmdline-tools
    $url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
        ok "cmdline-tools descargado"
    } catch { fail "No se pudo descargar Android cmdline-tools. Verifica conexión a internet." }

    # Extraer
    New-Item -ItemType Directory -Force $tmpDir | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    # Instalar en SDK path correcto
    $dest = Join-Path $SDK "cmdline-tools\latest"
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    if (Test-Path (Join-Path $tmpDir "cmdline-tools")) {
        Move-Item -Force (Join-Path $tmpDir "cmdline-tools") $dest
    } else { Move-Item -Force $tmpDir $dest }

    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    ok "cmdline-tools instalado en $dest"
}

# Aceptar licencias e instalar plataformas
$requiredPkgs = @(
    "platform-tools",
    "platforms;android-35",
    "build-tools;34.0.0",
    "build-tools;35.0.1"
)

$missing = $requiredPkgs | Where-Object {
    $path = $_ -replace ';','\'
    -not (Test-Path (Join-Path $SDK $path))
}

if ($missing) {
    step "Instalando componentes SDK: $($missing -join ', ')..."
    # Aceptar licencias automaticamente
    $licenses = "y`n" * 10
    $licenses | & $sdkManager --licenses 2>&1 | Out-Null

    foreach ($pkg in $missing) {
        warn "Instalando $pkg..."
        & $sdkManager $pkg 2>&1 | Select-Object -Last 2
    }
    ok "Componentes SDK instalados"
} else { ok "Android SDK components OK" }

# ── 4. Flutter doctor ────────────────────────────────────────
step "Verificando flutter doctor..."
$doctorOut = & flutter doctor 2>&1 | Out-String
$noAndroid = $doctorOut -match 'Android toolchain.*✗|Android SDK.*not found'
if ($noAndroid) {
    warn "Flutter no detecta Android SDK. Configurando..."
    & flutter config --android-sdk $SDK 2>&1 | Out-Null
    "y" | & flutter doctor --android-licenses 2>&1 | Out-Null
}
ok "Flutter configurado"

# ── 5. pub get ───────────────────────────────────────────────
step "Obteniendo dependencias Flutter..."
Set-Location $APPDIR
& flutter pub get 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { fail "flutter pub get falló" }
ok "Dependencias OK"

# ── 6. Clean (opcional) ──────────────────────────────────────
if ($Clean) {
    step "Limpiando build anterior..."
    & flutter clean 2>&1 | Out-Null
    ok "Clean completado"
}

# ── 7. Build APK ─────────────────────────────────────────────
step "Compilando APK release (puede tardar 5-10 min)..."
Write-Host "  → minSdk 23 | targetSdk 35 | compileSdk 35`n"

$buildOut = & flutter build apk --release --no-pub --obfuscate --split-debug-info="$APPDIR\debug-symbols" 2>&1
$buildOut | Select-String "error:|Error:|warning:" -ErrorAction SilentlyContinue | ForEach-Object { warn $_ }

if ($LASTEXITCODE -ne 0) {
    $buildOut | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    fail "flutter build apk falló (ver arriba)"
}

# ── 8. Copiar APK ────────────────────────────────────────────
$apkSrc = Join-Path $APPDIR "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkSrc) {
    Copy-Item $apkSrc $OUT -Force
    $size = [math]::Round((Get-Item $OUT).Length / 1MB, 1)
    Write-Host ""
    Write-Host "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
    Write-Host "${GREEN}${BOLD}║         APK COMPILADO EXITOSAMENTE         ║${NC}"
    Write-Host "${GREEN}${BOLD}╠════════════════════════════════════════════╣${NC}"
    Write-Host "${GREEN}${BOLD}║${NC} Archivo: app-release.apk (${size}MB)$((' ' * [Math]::Max(0, 19 - "$size".Length)))${GREEN}${BOLD}║${NC}"
    Write-Host "${GREEN}${BOLD}║${NC} Ruta:    $($OUT.Substring(0, [Math]::Min($OUT.Length, 44)).PadRight(44)) ${GREEN}${BOLD}║${NC}"
    Write-Host "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
    Write-Host ""
} else {
    fail "APK no encontrado en $apkSrc"
}
