#Requires -Version 5.1
# ================================================================
#  compilar-apk.ps1 -- Compila APK de Concentrados Monserrath
#  Instala automaticamente: Java 17, Android SDK, Flutter
#  Uso: .\compilar-apk.ps1
# ================================================================

param([switch]$Clean)

$ErrorActionPreference = 'Stop'
$PROJ   = Split-Path $MyInvocation.MyCommand.Path
$APPDIR = Join-Path $PROJ "android-app"
$SDK    = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$OUT    = Join-Path $PROJ "app-release.apk"

$GREEN = "`e[32m"; $YELLOW = "`e[33m"; $RED = "`e[31m"; $NC = "`e[0m"; $BOLD = "`e[1m"
function ok($m)   { Write-Host "${GREEN}OK${NC} $m" }
function warn($m) { Write-Host "${YELLOW}WARN${NC} $m" }
function step($m) { Write-Host "${BOLD}>> $m${NC}" }
function fail($m) { Write-Host "${RED}ERROR:${NC} $m"; exit 1 }

# Refresh PATH helper
function RefreshPath {
    $paths = @(
        "$env:USERPROFILE\scoop\shims",
        "$env:USERPROFILE\scoop\apps\flutter\current\bin",
        "$env:USERPROFILE\scoop\apps\temurin17-jdk\current\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) { $paths += (Split-Path $javaCmd.Source) }
    $env:PATH = ($paths + ($env:PATH -split ';') | Select-Object -Unique) -join ';'
}

Write-Host ""
Write-Host "${GREEN}${BOLD}+============================================+${NC}"
Write-Host "${GREEN}${BOLD}|  Compilador APK - Concentrados Monserrath  |${NC}"
Write-Host "${GREEN}${BOLD}+============================================+${NC}"
Write-Host ""

# Apply scoop PATH first
$env:PATH = "$env:USERPROFILE\scoop\shims;$env:USERPROFILE\scoop\apps\temurin17-jdk\current\bin;$env:USERPROFILE\scoop\apps\flutter\current\bin;$env:PATH"

# -- 1. Java 17 -----------------------------------------------
step "Verificando Java 17..."
$javaOk = $false
$jvVer   = ''

# cmd /c con 2>&1 DENTRO de las comillas: cmd procesa el redirect, no PS
# Evita ErrorRecord que termina con ErrorActionPreference=Stop
$jvRaw = cmd /c "java -version 2>&1"
$jvStr = ($jvRaw | ForEach-Object { "$_" }) -join ' '
if ($jvStr -match '"([^"]+)"') { $jvVer = $Matches[1] }
if ($jvStr -match '1[7-9]\.|2[0-9]\.') { $javaOk = $true }

if (-not $javaOk) {
    warn "Java 17 no encontrado. Instalando via Scoop..."
    try {
        & "$env:USERPROFILE\scoop\shims\scoop.cmd" bucket add java 2>$null
        & "$env:USERPROFILE\scoop\shims\scoop.cmd" install java/temurin17-jdk 2>&1 | Select-Object -Last 3
    } catch {
        warn "Scoop fallo, intentando winget..."
        & winget install EclipseAdoptium.Temurin.17.JDK -e --silent 2>&1 | Select-Object -Last 2
    }
    RefreshPath
    $jv2Str = (cmd /c "java -version 2>&1" | ForEach-Object { "$_" }) -join ' '
    if ($jv2Str -match '1[7-9]\.|2[0-9]\.') { ok "Java instalado" }
    else { fail "Java 17 no pudo instalarse. Instala desde https://adoptium.net" }
} else {
    ok "Java: $jvVer"
}

# Configurar JAVA_HOME
$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if ($javaCmd) {
    $env:JAVA_HOME = Split-Path (Split-Path $javaCmd.Source)
    ok "JAVA_HOME = $env:JAVA_HOME"
} else { fail "No se encontro java en PATH. Reinicia PowerShell e intenta de nuevo." }

# -- 2. Flutter -----------------------------------------------
step "Verificando Flutter..."
# Use junction C:\devflutter to avoid spaces-in-path bug with objective_c native assets hook
$FLUTTER = if (Test-Path "C:\devflutter\bin\flutter.bat") {
    "C:\devflutter\bin\flutter.bat"
} else {
    "$env:USERPROFILE\scoop\apps\flutter\current\bin\flutter.bat"
}
if (-not (Test-Path $FLUTTER)) {
    warn "Flutter no encontrado. Instalando via Scoop..."
    & "$env:USERPROFILE\scoop\shims\scoop.cmd" bucket add extras 2>$null
    & "$env:USERPROFILE\scoop\shims\scoop.cmd" install flutter 2>&1 | Select-Object -Last 3
    $env:PATH = "$env:USERPROFILE\scoop\apps\flutter\current\bin;$env:PATH"
    if (-not (Test-Path $FLUTTER)) { fail "Flutter no pudo instalarse." }
}
$fv = & $FLUTTER --version 2>&1 | Select-String "Flutter"
ok "Flutter: $($fv -replace 'Flutter (\S+).*','$1') [$FLUTTER]"

# -- 3. Android SDK -------------------------------------------
step "Verificando Android SDK..."
$env:ANDROID_HOME     = $SDK
$env:ANDROID_SDK_ROOT = $SDK
$env:PATH = "$SDK\cmdline-tools\latest\bin;$SDK\platform-tools;$SDK\build-tools\34.0.0;$env:PATH"

$sdkManager = Join-Path $SDK "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManager)) {
    warn "Android SDK no encontrado. Descargando cmdline-tools..."

    $tmpZip = Join-Path $env:TEMP "cmdline-tools.zip"
    $tmpDir = Join-Path $env:TEMP "cmdline-tools-extract"

    $url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
        ok "cmdline-tools descargado"
    } catch { fail "No se pudo descargar Android cmdline-tools. Verifica conexion a internet." }

    New-Item -ItemType Directory -Force $tmpDir | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

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
    $licenses = "y`n" * 10
    $licenses | & $sdkManager --licenses 2>&1 | Out-Null

    foreach ($pkg in $missing) {
        warn "Instalando $pkg..."
        & $sdkManager $pkg 2>&1 | Select-Object -Last 2
    }
    ok "Componentes SDK instalados"
} else { ok "Android SDK components OK" }

# -- 4. Flutter doctor (solo si SDK no está configurado) ------
step "Verificando configuración Android..."
$sdkConfigured = (Test-Path (Join-Path $SDK "platform-tools\adb.exe")) -and
                 ($env:ANDROID_HOME -or $env:ANDROID_SDK_ROOT)
if (-not $sdkConfigured) {
    warn "Configurando Android SDK en Flutter..."
    $ErrorActionPreference = 'Continue'
    & $FLUTTER config --android-sdk $SDK 2>&1 | Out-Null
    "y" | & $FLUTTER doctor --android-licenses 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
}
ok "Flutter configurado"

# -- 5. pub get (omite si pubspec.lock está actualizado) ------
step "Verificando dependencias Flutter..."
Set-Location $APPDIR
$pubLock    = Join-Path $APPDIR "pubspec.lock"
$pubYaml    = Join-Path $APPDIR "pubspec.yaml"
$pkgConfig  = Join-Path $APPDIR ".dart_tool\package_config.json"
$pubFresh   = (Test-Path $pubLock) -and (Test-Path $pkgConfig) -and
              ((Get-Item $pubLock).LastWriteTime -ge (Get-Item $pubYaml).LastWriteTime)
if (-not $pubFresh -or $Clean) {
    $ErrorActionPreference = 'Continue'
    & $FLUTTER pub get 2>&1 | Select-Object -Last 3
    $pubExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($pubExitCode -ne 0) { fail "flutter pub get fallo" }
    ok "Dependencias actualizadas"
} else {
    ok "Dependencias OK (cache)"
}

# -- 6. Clean (opcional) --------------------------------------
if ($Clean) {
    step "Limpiando build anterior..."
    $ErrorActionPreference = 'Continue'
    & $FLUTTER clean 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    ok "Clean completado"
}

# -- 6b. Gradle parallel build config -------------------------
step "Configurando Gradle para compilación rápida..."
$gradlePropsDir = Join-Path $APPDIR "android"
$gradlePropsFile = Join-Path $gradlePropsDir "gradle.properties"
$gradleOptsBlock = @"

# Performance — auto-agregado por compilar-apk.ps1
org.gradle.parallel=true
org.gradle.daemon=true
org.gradle.caching=true
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
"@
$currentContent = if (Test-Path $gradlePropsFile) { Get-Content $gradlePropsFile -Raw } else { "" }
if ($currentContent -notmatch 'org\.gradle\.parallel') {
    Add-Content -Path $gradlePropsFile -Value $gradleOptsBlock
    ok "Gradle: parallel + daemon + cache habilitados"
} else {
    ok "Gradle: configuración de rendimiento ya presente"
}

# -- 6c. Skip build if APK is newer than all Dart sources -----
$apkSrcPath = Join-Path $APPDIR "build\app\outputs\flutter-apk\app-release.apk"
if (-not $Clean -and (Test-Path $apkSrcPath)) {
    $apkTime = (Get-Item $apkSrcPath).LastWriteTime
    $dartFiles = Get-ChildItem -Path (Join-Path $APPDIR "lib") -Recurse -Filter "*.dart"
    $pubYamlTime = (Get-Item (Join-Path $APPDIR "pubspec.yaml")).LastWriteTime
    $newerFiles = $dartFiles | Where-Object { $_.LastWriteTime -gt $apkTime }
    if (-not $newerFiles -and $pubYamlTime -le $apkTime) {
        ok "APK está actualizado — no se necesita recompilar"
        $size = [math]::Round((Get-Item $apkSrcPath).Length / 1MB, 1)
        Copy-Item $apkSrcPath $OUT -Force
        Write-Host ""
        Write-Host "${GREEN}${BOLD}+============================================+${NC}"
        Write-Host "${GREEN}${BOLD}|    APK SIN CAMBIOS — COPIA DIRECTA         |${NC}"
        Write-Host "${GREEN}${BOLD}+--------------------------------------------+${NC}"
        Write-Host "${GREEN}${BOLD}|${NC} Archivo: app-release.apk (${size}MB)$((' ' * [Math]::Max(0, 19 - "$size".Length)))${GREEN}${BOLD}|${NC}"
        Write-Host "${GREEN}${BOLD}+============================================+${NC}"
        Write-Host ""
        exit 0
    }
    $changedCount = ($newerFiles | Measure-Object).Count
    ok "Cambios detectados ($changedCount archivos) — recompilando..."
}

# -- 7. Build APK ---------------------------------------------
step "Compilando APK release (arm64 optimizado)..."
Write-Host "  >> minSdk 23 | targetSdk 36 | platform arm64-only | Gradle paralelo`n"

# Flutter may write KGP WARNINGs to stderr — suspend Stop to avoid false failure
$ErrorActionPreference = 'Continue'
$buildOut = & $FLUTTER build apk --release --no-pub --target-platform android-arm64 --obfuscate --split-debug-info="$APPDIR\debug-symbols" 2>&1
$buildExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

$buildOut | Select-String "error:|Error:" -ErrorAction SilentlyContinue | ForEach-Object { warn $_ }

if ($buildExitCode -ne 0) {
    $buildOut | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    fail "flutter build apk fallo (ver arriba)"
}

# -- 8. Copiar APK --------------------------------------------
$apkSrc = Join-Path $APPDIR "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkSrc) {
    Copy-Item $apkSrc $OUT -Force
    $size = [math]::Round((Get-Item $OUT).Length / 1MB, 1)
    Write-Host ""
    Write-Host "${GREEN}${BOLD}+============================================+${NC}"
    Write-Host "${GREEN}${BOLD}|       APK COMPILADO EXITOSAMENTE           |${NC}"
    Write-Host "${GREEN}${BOLD}+--------------------------------------------+${NC}"
    Write-Host "${GREEN}${BOLD}|${NC} Archivo: app-release.apk (${size}MB)$((' ' * [Math]::Max(0, 19 - "$size".Length)))${GREEN}${BOLD}|${NC}"
    Write-Host "${GREEN}${BOLD}+============================================+${NC}"
    Write-Host ""
} else {
    fail "APK no encontrado en $apkSrc"
}
