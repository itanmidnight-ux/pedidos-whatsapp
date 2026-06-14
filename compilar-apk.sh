#!/usr/bin/env bash
# ================================================================
#  compilar-apk.sh — Build APK release de Concentrados Monserrath
#  Sistema : Linux (Kali / Ubuntu / Debian / Arch)
#  Uso     : bash compilar-apk.sh [--clean]
#  Req     : conexión a internet en primer uso
# ================================================================

set -euo pipefail

# ── Rutas ────────────────────────────────────────────────────────
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPDIR="$PROJ/android-app"
SDK="$HOME/Android/Sdk"
OUT="$PROJ/app-release.apk"
CLEAN="${1:-}"

# SDK versions requeridas por build.gradle.kts
COMPILE_SDK=36
TARGET_SDK=35
NDK_VERSION="28.2.13676358"
BUILD_TOOLS="35.0.1"

# ── Colores ───────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  [OK]${NC}  $1"; }
warn() { echo -e "${YELLOW}  [!] ${NC}  $1"; }
step() { echo -e "\n${BOLD}  >> $1${NC}"; }
die()  {
    echo -e "\n${RED}  [ERROR]${NC} $1"
    echo -e "${YELLOW}  Revisa el log completo arriba para más detalles.${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}${BOLD}  +================================================+${NC}"
echo -e "${GREEN}${BOLD}  |  Compilador APK — Concentrados Monserrath v2.0  |${NC}"
echo -e "${GREEN}${BOLD}  +================================================+${NC}"
echo ""

[ -d "$APPDIR" ]          || die "Directorio android-app no encontrado: $APPDIR"
[ -f "$APPDIR/pubspec.yaml" ] || die "pubspec.yaml no encontrado en $APPDIR"

# ── PASO 1: Java 17+ ─────────────────────────────────────────────
step "Verificando Java 17..."

JAVA_OK=false
if command -v java &>/dev/null; then
    JAVA_MAJ=$(java -version 2>&1 | grep -oP '(?<=")\d+' | head -1 || echo "0")
    [[ "${JAVA_MAJ:-0}" -ge 17 ]] && JAVA_OK=true
fi

if [ "$JAVA_OK" = "false" ]; then
    warn "Java 17 no encontrado — instalando openjdk-17..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y openjdk-17-jdk-headless 2>/dev/null \
            || sudo apt-get install -y openjdk-17-jdk \
            || die "Instala Java 17 manualmente: sudo apt install openjdk-17-jdk"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y java-17-openjdk-devel
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm jdk17-openjdk
    else
        die "Instala Java 17 desde https://adoptium.net y vuelve a ejecutar."
    fi
fi

# Preferir Java 17 si hay alternativas
if command -v update-alternatives &>/dev/null; then
    JV17=$(update-alternatives --list java 2>/dev/null | grep "java-17" | head -1 || true)
    [ -n "$JV17" ] && sudo update-alternatives --set java "$JV17" &>/dev/null || true
fi

JAVA_MAJ=$(java -version 2>&1 | grep -oP '(?<=")\d+' | head -1 || echo "0")
[[ "${JAVA_MAJ:-0}" -ge 17 ]] || die "Java 17+ requerido. Instalado: $JAVA_MAJ"

JAVA_BIN=$(readlink -f "$(which java)")
export JAVA_HOME="${JAVA_BIN%/bin/java}"
[[ -d "$JAVA_HOME" ]] || export JAVA_HOME="${JAVA_BIN%/jre/bin/java}"
ok "Java $JAVA_MAJ — JAVA_HOME=$JAVA_HOME"

# ── PASO 2: Flutter ──────────────────────────────────────────────
step "Verificando Flutter..."

FLUTTER=""
for loc in \
    "$(which flutter 2>/dev/null || true)" \
    "$HOME/flutter/bin/flutter" \
    "$HOME/.local/share/flutter/bin/flutter" \
    "/opt/flutter/bin/flutter" \
    "/snap/bin/flutter"; do
    [[ -n "$loc" ]] && [[ -f "$loc" ]] && { FLUTTER="$loc"; break; }
done

if [ -z "$FLUTTER" ]; then
    warn "Flutter no encontrado — instalando..."

    # Intentar snap
    if command -v snap &>/dev/null; then
        warn "Intentando via snap..."
        sudo snap install flutter --classic 2>/dev/null && {
            FLUTTER="$(which flutter 2>/dev/null || true)"
        } || true
    fi

    # Descarga directa si snap no funcionó
    if [ -z "$FLUTTER" ] || [ ! -f "$FLUTTER" ]; then
        warn "Descargando Flutter (latest stable)..."

        FLUTTER_DIR="$HOME/flutter"
        FLUTTER_URL=""

        # Intentar obtener latest stable via API
        if command -v python3 &>/dev/null; then
            FLUTTER_URL=$(python3 - <<'PYEOF' 2>/dev/null || true
import urllib.request, json, sys
try:
    with urllib.request.urlopen("https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json", timeout=15) as r:
        d = json.load(r)
        h = d["current_release"]["stable"]
        rel = next(x for x in d["releases"] if x["hash"] == h)
        print(d["base_url"] + "/" + rel["archive"])
except Exception as e:
    sys.exit(1)
PYEOF
        )
        fi

        # Fallback a versión conocida
        if [ -z "$FLUTTER_URL" ]; then
            warn "No se pudo obtener URL dinámica — usando versión estable conocida..."
            FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.2-stable.tar.xz"
        fi

        if [ ! -d "$FLUTTER_DIR/.git" ]; then
            warn "Descargando: $FLUTTER_URL"
            curl -fL --progress-bar "$FLUTTER_URL" -o /tmp/flutter_sdk.tar.xz \
                || die "Descarga de Flutter falló. Verifica conexión a Internet."
            warn "Extrayendo Flutter SDK..."
            tar xf /tmp/flutter_sdk.tar.xz -C "$HOME"
            rm -f /tmp/flutter_sdk.tar.xz
        fi

        FLUTTER="$FLUTTER_DIR/bin/flutter"
        export PATH="$FLUTTER_DIR/bin:$PATH"
        grep -qF 'flutter/bin' "$HOME/.bashrc" 2>/dev/null \
            || echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\"" >> "$HOME/.bashrc"
    fi
fi

[ -f "$FLUTTER" ] || die "Flutter no disponible en: $FLUTTER"

# Actualizar herramientas internas Flutter
"$FLUTTER" precache --android --no-ios --no-web --no-linux --no-macos --no-windows 2>/dev/null || true

FLUTTER_DIR="$(dirname "$(dirname "$FLUTTER")")"
FLUTTER_VER=$("$FLUTTER" --version 2>&1 | grep "^Flutter" | awk '{print $2}' || echo "?")
ok "Flutter $FLUTTER_VER — $FLUTTER_DIR"

# ── PASO 3: Android SDK ──────────────────────────────────────────
step "Verificando Android SDK (compileSdk $COMPILE_SDK, NDK $NDK_VERSION)..."

export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$SDK/build-tools/$BUILD_TOOLS:$PATH"

SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -f "$SDKMANAGER" ]; then
    warn "Android cmdline-tools no encontrado — descargando..."
    command -v unzip &>/dev/null || sudo apt-get install -y unzip -qq
    command -v wget  &>/dev/null || sudo apt-get install -y wget  -qq
    CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    curl -fsSL --progress-bar "$CMDTOOLS_URL" -o /tmp/cmdtools.zip \
        || die "No se pudo descargar Android cmdline-tools."
    mkdir -p /tmp/ct-extract
    unzip -q /tmp/cmdtools.zip -d /tmp/ct-extract
    mkdir -p "$SDK/cmdline-tools/latest"
    cp -r /tmp/ct-extract/cmdline-tools/. "$SDK/cmdline-tools/latest/"
    rm -rf /tmp/cmdtools.zip /tmp/ct-extract
fi
[ -f "$SDKMANAGER" ] || die "sdkmanager no encontrado en $SDKMANAGER"

# Aceptar licencias (silencioso)
yes 2>/dev/null | "$SDKMANAGER" --licenses &>/dev/null || true

# Componentes requeridos
declare -A SDK_CHECKS=(
    ["platform-tools"]="$SDK/platform-tools/adb"
    ["platforms;android-${COMPILE_SDK}"]="$SDK/platforms/android-${COMPILE_SDK}"
    ["platforms;android-${TARGET_SDK}"]="$SDK/platforms/android-${TARGET_SDK}"
    ["build-tools;${BUILD_TOOLS}"]="$SDK/build-tools/${BUILD_TOOLS}"
    ["ndk;${NDK_VERSION}"]="$SDK/ndk/${NDK_VERSION}"
)

MISSING_PKGS=()
for pkg in "${!SDK_CHECKS[@]}"; do
    check_path="${SDK_CHECKS[$pkg]}"
    [ -e "$check_path" ] || MISSING_PKGS+=("$pkg")
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    warn "Instalando componentes SDK faltantes..."
    for pkg in "${MISSING_PKGS[@]}"; do
        warn "  → $pkg"
        yes 2>/dev/null | "$SDKMANAGER" "$pkg" 2>&1 | grep -v "^Warning\|^Unzip\|^Prepare\|^\[=" | tail -3 || \
            warn "  Advertencia: no se pudo instalar $pkg (puede seguir si ya existe)"
    done
    ok "Componentes SDK instalados"
else
    ok "Android SDK OK (compileSdk $COMPILE_SDK, NDK $NDK_VERSION)"
fi

# Verificar NDK obligatorio
[ -d "$SDK/ndk/$NDK_VERSION" ] || die "NDK $NDK_VERSION no encontrado en $SDK/ndk/$NDK_VERSION\nEjecuta: $SDKMANAGER 'ndk;$NDK_VERSION'"

# Configurar Flutter con Android SDK
"$FLUTTER" config --android-sdk "$SDK" &>/dev/null || true

# ── PASO 4: local.properties ─────────────────────────────────────
step "Configurando local.properties..."

# settings.gradle.kts requiere flutter.sdk en local.properties
LOCAL_PROPS="$APPDIR/android/local.properties"
cat > "$LOCAL_PROPS" << EOF
sdk.dir=$SDK
flutter.sdk=$FLUTTER_DIR
ndk.dir=$SDK/ndk/$NDK_VERSION
EOF
ok "local.properties escrito: sdk=$SDK, flutter=$FLUTTER_DIR"

# ── PASO 5: Gradle performance ───────────────────────────────────
GRADLE_PROPS="$APPDIR/android/gradle.properties"
# Solo ajustar jvmargs si el valor actual es bajo (< 2GB)
CURRENT_XMX=$(grep 'org.gradle.jvmargs' "$GRADLE_PROPS" 2>/dev/null | grep -oP '(?<=-Xmx)\d+(?=[gGmM])' || echo "0")
CURRENT_UNIT=$(grep 'org.gradle.jvmargs' "$GRADLE_PROPS" 2>/dev/null | grep -oP '(?<=-Xmx\d{1,4})[gGmM]' || echo "m")
if [[ "${CURRENT_UNIT,,}" == "g" ]] && [[ "${CURRENT_XMX:-0}" -ge 2 ]]; then
    ok "Gradle JVM: ${CURRENT_XMX}G (OK)"
else
    # Detectar RAM disponible para asignar heap razonable
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "4000000")
    HEAP_MB=$(( TOTAL_MEM_KB / 1024 / 2 ))   # 50% de RAM total
    [[ $HEAP_MB -lt 2048 ]] && HEAP_MB=2048
    [[ $HEAP_MB -gt 6144 ]] && HEAP_MB=6144
    # Reemplazar o agregar jvmargs
    if grep -q 'org.gradle.jvmargs' "$GRADLE_PROPS" 2>/dev/null; then
        sed -i "s|^org.gradle.jvmargs=.*|org.gradle.jvmargs=-Xmx${HEAP_MB}m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8|" "$GRADLE_PROPS"
    else
        echo "org.gradle.jvmargs=-Xmx${HEAP_MB}m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8" >> "$GRADLE_PROPS"
    fi
    # Activar parallel + daemon
    grep -q 'org.gradle.parallel=' "$GRADLE_PROPS" 2>/dev/null \
        && sed -i "s|^org.gradle.parallel=.*|org.gradle.parallel=true|" "$GRADLE_PROPS" \
        || echo "org.gradle.parallel=true" >> "$GRADLE_PROPS"
    grep -q 'org.gradle.daemon=' "$GRADLE_PROPS" 2>/dev/null \
        && sed -i "s|^org.gradle.daemon=.*|org.gradle.daemon=true|" "$GRADLE_PROPS" \
        || echo "org.gradle.daemon=true" >> "$GRADLE_PROPS"
    ok "Gradle JVM heap ajustado a ${HEAP_MB}m, parallel=true, daemon=true"
fi

# ── PASO 6: Flutter pub get ──────────────────────────────────────
step "Verificando dependencias Flutter..."
cd "$APPDIR"

PUB_LOCK="$APPDIR/pubspec.lock"
PKG_CFG="$APPDIR/.dart_tool/package_config.json"

# ── PASO 7: Clean opcional (ANTES de pub get) ────────────────────
if [ "$CLEAN" = "--clean" ]; then
    step "Limpiando build anterior..."
    "$FLUTTER" clean 2>&1 | tail -2
    ok "Clean completado"
fi

# Fix permisos de archivos que pudieron quedar como root
sudo chown -R "$(id -u):$(id -g)" "$APPDIR/.dart_tool" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$APPDIR/.flutter-plugins" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$APPDIR/.flutter-plugins-dependencies" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$APPDIR/android/.gradle" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$APPDIR/android/local.properties" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$HOME/.gradle" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$HOME/.pub-cache" 2>/dev/null || true

NEEDS_PUBGET=true
if [ -f "$PUB_LOCK" ] && [ -f "$PKG_CFG" ] && \
   [ "$PUB_LOCK" -nt "$APPDIR/pubspec.yaml" ] && \
   [ "$CLEAN" != "--clean" ]; then
    NEEDS_PUBGET=false
fi

if [ "$NEEDS_PUBGET" = "true" ]; then
    warn "Resolviendo paquetes..."
    "$FLUTTER" pub get 2>&1 | grep -E "^Resolving|^Got|^Changed|^Downloading|Error" || true
    ok "Dependencias resueltas"
else
    ok "Dependencias OK (cache — usa --clean para forzar)"
fi

# ── PASO 8: Verificar fuentes vs APK existente ───────────────────
APK_BUILD="$APPDIR/build/app/outputs/flutter-apk/app-release.apk"

if [ "$CLEAN" != "--clean" ] && [ -f "$APK_BUILD" ]; then
    NEWER=$(find "$APPDIR/lib" -name "*.dart" -newer "$APK_BUILD" 2>/dev/null | wc -l)
    PUB_NEWER=0
    [ "$APPDIR/pubspec.yaml" -nt "$APK_BUILD" ] 2>/dev/null && PUB_NEWER=1

    if [[ "$NEWER" -eq 0 ]] && [[ "$PUB_NEWER" -eq 0 ]]; then
        cp "$APK_BUILD" "$OUT"
        SIZE=$(du -sh "$OUT" 2>/dev/null | cut -f1)
        echo ""
        echo -e "${GREEN}${BOLD}  +================================================+${NC}"
        echo -e "${GREEN}${BOLD}  |  APK SIN CAMBIOS — COPIA DIRECTA               |${NC}"
        echo -e "${GREEN}${BOLD}  +------------------------------------------------+${NC}"
        echo -e "${GREEN}  |${NC}  Archivo : ${BOLD}app-release.apk${NC} ($SIZE)"
        echo -e "${GREEN}  |${NC}  Ruta    : $OUT"
        echo -e "${GREEN}${BOLD}  +================================================+${NC}"
        echo ""
        exit 0
    fi
    warn "$NEWER archivo(s) Dart modificados — recompilando..."
fi

# ── PASO 9: Compilar APK release ─────────────────────────────────
step "Compilando APK release (puede tardar 3-10 min en primer build)..."
echo -e "  compileSdk=$COMPILE_SDK | targetSdk=$TARGET_SDK | minSdk=23"
echo -e "  NDK=$NDK_VERSION | build-tools=$BUILD_TOOLS | R8=ON\n"

# Re-escribir local.properties justo antes del build (Flutter puede sobreescribirlo)
cat > "$LOCAL_PROPS" << LOCALEOF
sdk.dir=$SDK
flutter.sdk=$FLUTTER_DIR
ndk.dir=$SDK/ndk/$NDK_VERSION
LOCALEOF

cd "$APPDIR"
"$FLUTTER" build apk \
    --release \
    --no-pub \
    --obfuscate \
    --split-debug-info="$PROJ/debug-symbols" \
    2>&1

BUILD_STATUS=$?
[ "$BUILD_STATUS" -eq 0 ] || die "flutter build apk falló con código $BUILD_STATUS"

# ── PASO 10: Copiar APK al directorio raíz ───────────────────────
[ -f "$APK_BUILD" ] || die "APK no generado en: $APK_BUILD"

cp "$APK_BUILD" "$OUT"
SIZE=$(du -sh "$OUT" 2>/dev/null | cut -f1)
VERSION=$(grep '^version:' "$APPDIR/pubspec.yaml" | awk '{print $2}')

echo ""
echo -e "${GREEN}${BOLD}  +================================================+${NC}"
echo -e "${GREEN}${BOLD}  |       APK COMPILADO EXITOSAMENTE               |${NC}"
echo -e "${GREEN}${BOLD}  +------------------------------------------------+${NC}"
echo -e "${GREEN}  |${NC}  Versión : ${BOLD}$VERSION${NC}"
echo -e "${GREEN}  |${NC}  Tamaño  : ${BOLD}$SIZE${NC}"
echo -e "${GREEN}  |${NC}  Archivo : ${BOLD}app-release.apk${NC}"
echo -e "${GREEN}  |${NC}  Ruta    : $OUT"
echo -e "${GREEN}${BOLD}  +================================================+${NC}"
echo ""
echo -e "  Instala en dispositivo:"
echo -e "  ${YELLOW}adb install -r $OUT${NC}"
echo ""
