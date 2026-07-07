#!/usr/bin/env bash
# ================================================================
#  deploy-linux.sh — Concentrados Monserrath v2.0
#  Instalacion, despliegue y gestion del servidor en Linux
#
#  Uso:
#    ./deploy-linux.sh              Instala/actualiza y despliega
#    ./deploy-linux.sh --menu       Abre el panel de gestion (GUI TUI)
#    ./deploy-linux.sh --uninstall  Detiene y elimina los servicios instalados
#
#  Requiere: root (el script se auto-eleva con sudo si hace falta).
#  Gestiona TODA la seguridad del servidor: usuario dedicado, firewall,
#  fail2ban, systemd hardening, secretos. Por eso necesita privilegios
#  totales — no hay modo degradado "sin root".
#  Probado en: Debian/Ubuntu/Kali. Detecta apt/dnf/pacman automaticamente.
# ================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Auto-elevacion a root ─────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

# Usuario real que invoco el script (para no dejar archivos del repo como root)
REAL_USER="${SUDO_USER:-$(id -un)}"

# ── Rutas y constantes ────────────────────────────────────────────
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$PROJ/server"
ENV_FILE="$SERVER_DIR/.env"
DEPLOY_CONF="$PROJ/.deploy-config"      # solo preferencias, nunca secretos
SERVICE_USER="pedidos-bot"
NODE_SVC="pedidos-bot"
CF_SVC="pedidos-bot-tunnel"
DEFAULT_PORT=3000
NODE_MAJOR=20
APPDATA_BOT="/var/lib/pedidos-bot"
LOG_DIR="/var/log/pedidos-bot"

# ── Colores / helpers de consola ─────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  [OK]${NC}  $1"; }
warn() { echo -e "${YELLOW}  [!] ${NC}  $1"; }
info() { echo -e "${CYAN}  >>  ${NC}  $1"; }
step() { echo -e "\n${BOLD}  == $1${NC}"; }
die()  { echo -e "\n${RED}  [ERROR]${NC} $1"; exit 1; }

has_cmd() { command -v "$1" &>/dev/null; }

# Ya somos root (auto-elevado arriba) — as_root es solo semantico, ejecuta directo.
as_root() { "$@"; }

# ── Detectar gestor de paquetes ───────────────────────────────────
PKG_MGR=""
if   has_cmd apt-get; then PKG_MGR="apt"
elif has_cmd dnf;     then PKG_MGR="dnf"
elif has_cmd pacman;  then PKG_MGR="pacman"
fi

pkg_install() {
    # Instala paquetes del sistema si hay privilegios; si no, solo advierte.
    [ -z "$PKG_MGR" ] && { warn "Gestor de paquetes desconocido — instala manualmente: $*"; return 1; }
    case "$PKG_MGR" in
        apt)    as_root apt-get update -qq &>/dev/null || true
                as_root apt-get install -y -qq "$@" ;;
        dnf)    as_root dnf install -y -q "$@" ;;
        pacman) as_root pacman -S --noconfirm --needed "$@" ;;
    esac
}

# ================================================================
#  GUI — ventana de escritorio real (zenity/GTK) con fallback a
#  whiptail (terminal) y a texto plano si no hay ninguno disponible.
# ================================================================
# El script corre como root (auto-elevado), pero los dialogos deben
# dibujarse en la sesion X del usuario que lo invoco, no en la de root
# -- root normalmente no tiene permiso sobre el Xauthority del usuario.
# Se ejecuta zenity como REAL_USER preservando DISPLAY/XAUTHORITY.
REAL_USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
export DISPLAY="${DISPLAY:-:0.0}"
export XAUTHORITY="${XAUTHORITY:-$REAL_USER_HOME/.Xauthority}"

HAS_ZENITY=false
if [ "${DEPLOY_NO_GUI:-}" != "1" ] && has_cmd zenity && [ -n "${DISPLAY:-}" ] && [ "$REAL_USER" != "root" ]; then
    HAS_ZENITY=true
fi
gui() { sudo -u "$REAL_USER" env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" zenity "$@"; }

HAS_WHIPTAIL=false
has_cmd whiptail && HAS_WHIPTAIL=true
# Sesiones sin terminal real (cron, CI, SSH sin pty) no pueden dibujar whiptail
# -- forzar modo texto plano con DEPLOY_NO_GUI=1.
[ "${DEPLOY_NO_GUI:-}" = "1" ] && HAS_WHIPTAIL=false

# Tema visual "Olivo & Ambar" (mismos colores de marca que la app) para
# que el panel de whiptail se sienta parte del mismo producto, no una
# herramienta generica pegada encima.
export NEWT_COLORS='
root=white,black
window=black,white
border=green,white
shadow=black,black
title=black,green
button=white,green
actbutton=black,brown
compactbutton=black,white
checkbox=black,white
actcheckbox=white,green
entry=black,white
disentry=black,white
label=black,white
listbox=black,white
actlistbox=white,green
textbox=black,white
acttextbox=white,green
helpline=white,black
roottext=white,black
emptyscale=,white
fullscale=,green
'

TITLE="Concentrados Monserrath — Panel de Servidor"

splash() {
    # zenity con --timeout devuelve exit 5 cuando el tiempo expira -- eso es
    # exito, no error, pero bajo set -e mataba el script entero aqui mismo
    # sin ningun output visible. "|| true" en ambas ramas evita el problema.
    if $HAS_ZENITY; then
        gui --info --title="$TITLE" --width=420 --timeout=2 \
            --text="<b>CONCENTRADOS MONSERRATH v2.0</b>\n\nPanel de despliegue y gestion del servidor" &>/dev/null || true
    elif $HAS_WHIPTAIL; then
        whiptail --title "$TITLE" --infobox "\n   +==============================================+\n   |                                                |\n   |     CONCENTRADOS MONSERRATH  -  v2.0          |\n   |     Panel de despliegue y gestion del server  |\n   |                                                |\n   +==============================================+\n" 12 62 || true
        sleep 2
    fi
}

ui_msg() {
    # Cerrar/Escapar el dialogo puede devolver exit != 0 -- eso NO es un error
    # del script, solo el usuario cerrando un aviso. "|| true" evita que
    # set -e mate el despliegue entero por un click de cierre.
    if $HAS_ZENITY; then gui --info --title="$TITLE" --width=560 --text="$1" 2>/dev/null || true
    elif $HAS_WHIPTAIL; then whiptail --title "$TITLE" --msgbox "$1" 16 74 || true
    else echo -e "\n$1\n"; read -rp "Enter para continuar..." _; fi
}
ui_input() {
    # ui_input "titulo" "default" -> stdout. Si se cancela el dialogo, cae al
    # valor por defecto en vez de matar el script (mismo motivo que ui_msg).
    local out
    if $HAS_ZENITY; then out=$(gui --entry --title="$TITLE" --width=480 --text="$1" --entry-text="$2" 2>/dev/null) || out="$2"
    elif $HAS_WHIPTAIL; then out=$(whiptail --title "$TITLE" --inputbox "$1" 10 70 "$2" 3>&1 1>&2 2>&3) || out="$2"
    else read -rp "$1 [$2]: " _v; out="${_v:-$2}"; fi
    echo "$out"
}
ui_yesno() {
    if $HAS_ZENITY; then gui --question --title="$TITLE" --width=480 --text="$1" 2>/dev/null
    elif $HAS_WHIPTAIL; then whiptail --title "$TITLE" --yesno "$1" 10 70
    else read -rp "$1 [s/N]: " _v; [[ "$_v" =~ ^[sSyY] ]]; fi
}
ui_menu() {
    # ui_menu "titulo" opt1 desc1 opt2 desc2 ... -> stdout = opcion elegida
    local title="$1"; shift
    if $HAS_ZENITY; then
        local rows=() first=true
        while [ $# -gt 0 ]; do
            if $first; then rows+=(TRUE "$1" "$2"); first=false
            else rows+=(FALSE "$1" "$2"); fi
            shift 2
        done
        gui --list --radiolist --title="$TITLE" --width=680 --height=560 \
            --text="$title" --column="" --column="Opcion" --column="Accion" \
            --print-column=2 --hide-column=2 "${rows[@]}" 2>/dev/null || echo 0
    elif $HAS_WHIPTAIL; then
        whiptail --title "$TITLE" --menu "$title" 24 78 14 "$@" 3>&1 1>&2 2>&3 || echo 0
    else
        echo "$title"
        local i=1 opts=()
        while [ $# -gt 0 ]; do echo "  $1) $2"; opts+=("$1"); shift 2; done
        read -rp "Elige opcion: " _c; echo "$_c"
    fi
}

# ================================================================
#  Utilidades de red / seguridad
# ================================================================
gen_secret() { openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p | tr -d '\n'; }

port_in_use() {
    local p="$1"
    # Debian/Kali bash se compila sin /dev/tcp; usar ss (o curl como fallback).
    if has_cmd ss; then ss -Htln "( sport = :$p )" 2>/dev/null | grep -q ":$p" && return 0 || return 1; fi
    curl -fsS --connect-timeout 1 "http://127.0.0.1:${p}/" &>/dev/null && return 0
    return 1
}

# Escribe .env preservando lo existente, solo agrega/actualiza claves dadas
env_set() {
    local key="$1" val="$2"
    touch "$ENV_FILE"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
}
env_get() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true; }

save_conf() { local key="$1" val="$2"; touch "$DEPLOY_CONF"
    if grep -q "^${key}=" "$DEPLOY_CONF" 2>/dev/null; then sed -i "s|^${key}=.*|${key}=${val}|" "$DEPLOY_CONF"
    else echo "${key}=${val}" >> "$DEPLOY_CONF"; fi
}
load_conf() { grep "^${1}=" "$DEPLOY_CONF" 2>/dev/null | head -1 | cut -d= -f2- || true; }

# ================================================================
#  PASO 1 — Node.js 20 LTS
# ================================================================
install_node() {
    step "Node.js $NODE_MAJOR LTS"
    # Match EXACTO de major version, no ">=". better-sqlite3 (modulo nativo,
    # compila contra los headers de V8) rompe en tiempo de compilacion con
    # versiones de Node mas nuevas que las que soporta esa release del
    # paquete -- un Node 24 "mas nuevo" no sirve, hace falta el mismo major
    # que usa el resto del proyecto.
    if has_cmd node; then
        local v; v=$(node --version 2>/dev/null | grep -oE '^v[0-9]+' | tr -d v)
        if [ "${v:-0}" -eq "$NODE_MAJOR" ]; then ok "Node.js $(node --version) ya instalado"; return 0; fi
        warn "Node.js instalado es v$v, se requiere exactamente v$NODE_MAJOR (modulos nativos como better-sqlite3 no compilan con otras majors)"
    fi

    # Instalacion standalone en /opt (no se toca el Node del sistema si
    # existe uno de otra version -- evita romper otras herramientas que
    # dependan de el).
    warn "Instalando Node.js $NODE_MAJOR standalone en /opt/nodejs..."
    local arch; arch=$(uname -m); case "$arch" in x86_64) arch=x64;; aarch64) arch=arm64;; esac
    local url="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/"
    local fname; fname=$(curl -fsSL "$url" | grep -oE "node-v${NODE_MAJOR}\.[0-9.]+-linux-${arch}\.tar\.xz" | head -1)
    [ -n "$fname" ] || die "No se pudo determinar la version de Node $NODE_MAJOR para descargar."
    mkdir -p /opt/nodejs
    curl -fsSL "${url}${fname}" -o /tmp/node.tar.xz || die "Descarga de Node.js fallo."
    tar xf /tmp/node.tar.xz -C /opt/nodejs
    rm -f /tmp/node.tar.xz
    local nodedir; nodedir=$(find /opt/nodejs -maxdepth 1 -iname "node-v${NODE_MAJOR}*" | head -1)
    ln -sfn "$nodedir" /opt/nodejs/current
    ln -sf /opt/nodejs/current/bin/node /usr/local/bin/node
    ln -sf /opt/nodejs/current/bin/npm  /usr/local/bin/npm
    ln -sf /opt/nodejs/current/bin/npx  /usr/local/bin/npx
    export PATH="/opt/nodejs/current/bin:$PATH"
    hash -r
    has_cmd node || die "Node.js no se pudo instalar."
    ok "Node.js $(node --version)"
}

# ================================================================
#  PASO 2 — Usuario de sistema dedicado (nunca correr el bot como root)
# ================================================================
setup_service_user() {
    step "Usuario de servicio sin privilegios ($SERVICE_USER)"
    if ! id "$SERVICE_USER" &>/dev/null; then
        as_root useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER" \
            && ok "Usuario de sistema '$SERVICE_USER' creado (sin shell, sin login)" \
            || { warn "No se pudo crear el usuario — se usara $(id -un)"; SERVICE_USER="$(id -un)"; }
    else
        ok "Usuario '$SERVICE_USER' ya existe"
    fi
    for d in "$APPDATA_BOT" "$APPDATA_BOT/media" "$APPDATA_BOT/docs" "$APPDATA_BOT/product-images" \
             "$APPDATA_BOT/estados" "$APPDATA_BOT/auth" "$APPDATA_BOT/branding" "$APPDATA_BOT/reports" \
             "$APPDATA_BOT/profile-pics" "$LOG_DIR"; do
        as_root mkdir -p "$d"
        as_root chown -R "$SERVICE_USER" "$d" 2>/dev/null || true
        as_root chmod 750 "$d" 2>/dev/null || true
    done

    # El repo suele vivir dentro del home de quien lo clono (ej. /home/kali/...),
    # y los home directories normalmente son 700 -- el usuario de servicio no
    # puede ni atravesarlos. Se otorga SOLO permiso de transito (x, sin lectura
    # ni listado) al home del usuario real, nunca al resto de su contenido.
    case "$PROJ" in
        "$REAL_USER_HOME"/*)
            if [ "$SERVICE_USER" != "$REAL_USER" ]; then
                has_cmd setfacl || pkg_install acl
                if has_cmd setfacl; then
                    setfacl -m "u:${SERVICE_USER}:x" "$REAL_USER_HOME" 2>/dev/null \
                        && ok "ACL: '$SERVICE_USER' puede atravesar $REAL_USER_HOME (sin leer/listar su contenido)" \
                        || warn "No se pudo aplicar ACL de transito en $REAL_USER_HOME"
                else
                    warn "setfacl no disponible — el servicio podria fallar con 'Permission denied' al iniciar (instala el paquete 'acl')"
                fi
            fi
            ;;
    esac
}

# ================================================================
#  PASO 3 — Dependencias npm
# ================================================================
install_npm_deps() {
    step "Dependencias npm"
    cd "$SERVER_DIR"
    if [ ! -d node_modules ] || [ package.json -nt node_modules/.package-lock.json 2>/dev/null ]; then
        warn "Instalando dependencias (npm ci --omit=dev)..."
        npm ci --omit=dev 2>&1 | tail -5 || npm install --omit=dev 2>&1 | tail -5
        ok "Dependencias instaladas"
    else
        ok "Dependencias npm OK (cache)"
    fi
    # better-sqlite3 es un modulo nativo (ABI ligado a la version exacta de
    # Node) -- si el binario ya en disco fue compilado para otro Node (ej.
    # el sistema tenia una version distinta antes), recompilar para evitar
    # el clasico "NODE_MODULE_VERSION X vs Y" al arrancar el servicio.
    if ! node -e "require('better-sqlite3')" &>/dev/null; then
        warn "better-sqlite3 no coincide con este Node — recompilando..."
        npm rebuild better-sqlite3 2>&1 | tail -5
        node -e "require('better-sqlite3')" &>/dev/null && ok "better-sqlite3 recompilado OK" \
            || warn "better-sqlite3 sigue fallando — revisa manualmente (build-essential/python3 instalados?)"
    fi
    restore_repo_ownership
}

# El script corre como root; el repo debe seguir siendo del usuario real,
# no de root, para que el desarrollador pueda seguir editando/commiteando.
# server/.env se re-asigna a SERVICE_USER despues porque systemd lo lee con ese usuario.
restore_repo_ownership() {
    [ "$REAL_USER" != "root" ] && chown -R "$REAL_USER" "$PROJ" 2>/dev/null || true
    [ -f "$ENV_FILE" ] && chown "$SERVICE_USER" "$ENV_FILE" 2>/dev/null || true
}

# ================================================================
#  PASO 4 — .env con secretos criptograficos, HOST solo localhost
# ================================================================
configure_env() {
    step "Configuracion (.env)"
    local port; port=$(load_conf PORT); port="${port:-$DEFAULT_PORT}"

    if [ ! -f "$ENV_FILE" ]; then
        warn "Generando .env con secretos aleatorios..."
        {
            echo "PORT=$port"
            echo "HOST=127.0.0.1"
            echo "NODE_ENV=production"
            echo "API_KEY=$(gen_secret)"
            echo "JWT_SECRET=$(gen_secret)"
            echo "BOT_ENABLED=true"
            echo "BOT_PHONE="
            # Estado persistente (DB, PDFs) vive en APPDATA_BOT, nunca dentro
            # del arbol de codigo -- asi el directorio del server puede quedar
            # 100% solo-lectura para el servicio systemd (ProtectHome=read-only).
            echo "DB_PATH=$APPDATA_BOT/pedidos.db"
            echo "REPORTS_DIR=$APPDATA_BOT/reports"
        } > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        ok ".env creado (permisos 600, HOST=127.0.0.1 — el puerto de Node NUNCA se expone directo a internet)"
    else
        ok ".env ya existe — no se sobreescriben secretos"
        chmod 600 "$ENV_FILE" 2>/dev/null || true
    fi
    [ -n "$(env_get API_KEY)" ]    || env_set API_KEY "$(gen_secret)"
    [ -n "$(env_get JWT_SECRET)" ] || env_set JWT_SECRET "$(gen_secret)"
    [ -n "$(env_get DB_PATH)" ]      || env_set DB_PATH "$APPDATA_BOT/pedidos.db"
    [ -n "$(env_get REPORTS_DIR)" ]  || env_set REPORTS_DIR "$APPDATA_BOT/reports"
    port=$(env_get PORT); port="${port:-$DEFAULT_PORT}"
    save_conf PORT "$port"
    as_root chown "$SERVICE_USER" "$ENV_FILE" 2>/dev/null || true
}

# ================================================================
#  PASO 5 — systemd: servicio Node hardened
# ================================================================
install_systemd_service() {
    step "Servicio systemd ($NODE_SVC)"
    local node_bin; node_bin="$(command -v node)"
    local unit="/etc/systemd/system/${NODE_SVC}.service"
    as_root tee "$unit" > /dev/null <<EOF
[Unit]
Description=Concentrados Monserrath - Servidor de pedidos WhatsApp
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SERVER_DIR
EnvironmentFile=$ENV_FILE
Environment=APPDATA=$(dirname "$APPDATA_BOT")
ExecStart=$node_bin $SERVER_DIR/src/index.js
Restart=on-failure
RestartSec=5

# ── Cyberseguridad: hardening systemd ─────────────────────────
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
# MemoryDenyWriteExecute=yes NO se usa: rompe el JIT de V8/Node (SIGTRAP al
# arrancar) -- es un incompatibilidad conocida entre systemd y runtimes JIT.
ReadWritePaths=$APPDATA_BOT $LOG_DIR
CapabilityBoundingSet=
AmbientCapabilities=

StandardOutput=append:$LOG_DIR/server.log
StandardError=append:$LOG_DIR/server.log

[Install]
WantedBy=multi-user.target
EOF
    as_root systemctl daemon-reload
    as_root systemctl enable "$NODE_SVC" &>/dev/null
    as_root systemctl restart "$NODE_SVC"
    ok "Servicio '$NODE_SVC' instalado y habilitado (auto-inicio + hardening systemd)"
}

wait_server_healthy() {
    local port="$1" tries="${2:-45}"
    info "Esperando que el servidor responda (max ${tries}s)..."
    for ((i=0; i<tries; i++)); do
        if curl -fsS "http://127.0.0.1:${port}/health" &>/dev/null; then ok "Servidor respondiendo en :$port"; return 0; fi
        sleep 1
    done
    warn "El servidor no respondio a tiempo — revisa: journalctl -u $NODE_SVC -n 50"
    return 1
}

# ================================================================
#  PASO 6 — Firewall: cerrar todo salvo lo estrictamente necesario
# ================================================================
harden_firewall() {
    step "Firewall (deny-by-default, solo abre lo necesario)"
    local expose_http="$1"   # true si se usara nginx en 80/443 directo (sin tunel)

    if has_cmd ufw; then
        as_root ufw --force enable &>/dev/null || true
        as_root ufw default deny incoming &>/dev/null || true
        as_root ufw default allow outgoing &>/dev/null || true
        as_root ufw allow OpenSSH &>/dev/null || as_root ufw allow 22/tcp &>/dev/null || true
        if [ "$expose_http" = "true" ]; then
            as_root ufw allow 80/tcp  &>/dev/null || true
            as_root ufw allow 443/tcp &>/dev/null || true
        fi
        ok "ufw activo — solo SSH$( [ "$expose_http" = "true" ] && echo ' + 80/443')  permitidos entrantes"
    elif has_cmd firewall-cmd; then
        as_root systemctl enable --now firewalld &>/dev/null || true
        as_root firewall-cmd --set-default-zone=drop &>/dev/null || true
        as_root firewall-cmd --permanent --add-service=ssh &>/dev/null || true
        if [ "$expose_http" = "true" ]; then
            as_root firewall-cmd --permanent --add-service=http  &>/dev/null || true
            as_root firewall-cmd --permanent --add-service=https &>/dev/null || true
        fi
        as_root firewall-cmd --reload &>/dev/null || true
        ok "firewalld activo (zona drop) — solo SSH$( [ "$expose_http" = "true" ] && echo ' + 80/443')"
    elif has_cmd iptables; then
        warn "ufw/firewalld no disponibles — aplicando reglas iptables minimas..."
        as_root iptables -P INPUT DROP 2>/dev/null || true
        as_root iptables -P FORWARD DROP 2>/dev/null || true
        as_root iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
        as_root iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        as_root iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
        if [ "$expose_http" = "true" ]; then
            as_root iptables -A INPUT -p tcp --dport 80  -j ACCEPT 2>/dev/null || true
            as_root iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        fi
        if has_cmd netfilter-persistent; then as_root netfilter-persistent save &>/dev/null || true
        else warn "Instala 'iptables-persistent' para que las reglas sobrevivan reinicios."; fi
        ok "iptables: politica DROP por defecto, solo SSH$( [ "$expose_http" = "true" ] && echo ' + 80/443') permitidos"
    else
        warn "No se encontro ufw/firewalld/iptables — omite hardening de firewall."
    fi
    warn "El puerto de Node ($(env_get PORT)) esta bound a 127.0.0.1 — nunca es alcanzable desde fuera del servidor, sin importar el firewall."
}

# ================================================================
#  PASO 7 — fail2ban (fuerza bruta SSH)
# ================================================================
install_fail2ban() {
    step "fail2ban (proteccion fuerza bruta SSH)"
    has_cmd fail2ban-client && { ok "fail2ban ya instalado"; as_root systemctl enable --now fail2ban &>/dev/null || true; return 0; }
    pkg_install fail2ban && {
        as_root tee /etc/fail2ban/jail.d/pedidos-bot.local >/dev/null <<'EOF' 2>/dev/null || true
[sshd]
enabled = true
maxretry = 5
bantime = 3600
findtime = 600
EOF
        as_root systemctl enable --now fail2ban &>/dev/null || true
        ok "fail2ban instalado y protegiendo SSH"
    } || warn "No se pudo instalar fail2ban — instalalo manualmente para mayor seguridad."
}

# ================================================================
#  PASO 8 — Acceso publico: cloudflared (recomendado, sin abrir puertos)
#           o nginx+certbot (alternativa, requiere 80/443 abiertos)
# ================================================================
install_cloudflared() {
    step "cloudflared (tunel HTTPS saliente — no requiere abrir puertos)"
    if has_cmd cloudflared; then ok "cloudflared ya instalado"; return 0; fi
    local arch; arch=$(uname -m); case "$arch" in x86_64) arch=amd64;; aarch64) arch=arm64;; esac
    local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"
    curl -fsSL "$url" -o /tmp/cloudflared || { warn "Descarga de cloudflared fallo"; return 1; }
    chmod +x /tmp/cloudflared
    mv /tmp/cloudflared /usr/local/bin/cloudflared
    ok "cloudflared instalado en /usr/local/bin"
}

setup_cloudflared_tunnel() {
    local port="$1"
    has_cmd cloudflared || { warn "cloudflared no disponible — omite tunel."; return 1; }
    local cf_bin; cf_bin="$(command -v cloudflared)"
    local unit="/etc/systemd/system/${CF_SVC}.service"
    as_root tee "$unit" > /dev/null <<EOF
[Unit]
Description=Concentrados Monserrath - Tunel Cloudflare
After=network-online.target ${NODE_SVC}.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
ExecStart=$cf_bin tunnel --url http://127.0.0.1:$port --no-autoupdate
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/tunnel.log
StandardError=append:$LOG_DIR/tunnel.log

[Install]
WantedBy=multi-user.target
EOF
    : > "$LOG_DIR/tunnel.log" 2>/dev/null || as_root sh -c ": > '$LOG_DIR/tunnel.log'"
    as_root systemctl daemon-reload
    as_root systemctl enable "$CF_SVC" &>/dev/null
    as_root systemctl restart "$CF_SVC"

    info "Esperando URL publica del tunel (max 30s)..."
    local tunnel_url=""
    for ((i=0; i<15; i++)); do
        sleep 2
        tunnel_url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/tunnel.log" 2>/dev/null | tail -1 || true)
        [ -n "$tunnel_url" ] && break
    done
    if [ -n "$tunnel_url" ]; then
        ok "Tunel activo: $tunnel_url"
        save_conf TUNNEL_URL "$tunnel_url"
    else
        warn "URL aun no aparece — revisa: $LOG_DIR/tunnel.log"
    fi
}

setup_nginx_certbot() {
    local port="$1" domain="$2"
    step "nginx + Let's Encrypt (dominio: $domain)"
    pkg_install nginx || warn "No se pudo instalar nginx."
    has_cmd nginx || { warn "nginx no disponible — omite reverse proxy."; return 1; }

    as_root tee "/etc/nginx/sites-available/pedidos-bot" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass         http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        client_max_body_size 50M;
    }
}
EOF
    as_root ln -sf /etc/nginx/sites-available/pedidos-bot /etc/nginx/sites-enabled/pedidos-bot 2>/dev/null || true
    as_root nginx -t &>/dev/null && as_root systemctl reload nginx || as_root systemctl restart nginx
    ok "nginx: reverse proxy 80 -> 127.0.0.1:$port"

    if pkg_install certbot python3-certbot-nginx; then
        as_root certbot --nginx -d "$domain" --non-interactive --agree-tos -m "admin@${domain}" --redirect \
            && ok "Certificado HTTPS (Let's Encrypt) instalado para $domain" \
            || warn "certbot fallo — revisa DNS de $domain apunte a esta IP y reintenta: certbot --nginx -d $domain"
    else
        warn "certbot no disponible — instalalo para HTTPS: apt install certbot python3-certbot-nginx"
    fi
}

# ================================================================
#  PASO 9 — DuckDNS (opcional)
# ================================================================
setup_duckdns() {
    local subdomain="$1" token="$2"
    step "DuckDNS ($subdomain.duckdns.org)"
    [ -n "$token" ] || { warn "Sin token DuckDNS — se omite."; return 0; }
    local rc; rc=$(curl -fsS "https://www.duckdns.org/update?domains=${subdomain}&token=${token}&ip=" 2>/dev/null || echo "ERROR")
    [ "$rc" = "OK" ] && ok "DuckDNS actualizado" || warn "DuckDNS respondio: $rc"

    if [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
        as_root tee "/etc/systemd/system/duckdns-pedidos-bot.service" >/dev/null <<EOF
[Unit]
Description=DuckDNS update - pedidos-bot
[Service]
Type=oneshot
ExecStart=/usr/bin/curl -fsS "https://www.duckdns.org/update?domains=${subdomain}&token=${token}&ip="
EOF
        as_root tee "/etc/systemd/system/duckdns-pedidos-bot.timer" >/dev/null <<'EOF'
[Unit]
Description=DuckDNS update timer - pedidos-bot
[Timer]
OnBootSec=1min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
        as_root systemctl daemon-reload
        as_root systemctl enable --now duckdns-pedidos-bot.timer &>/dev/null
        ok "DuckDNS: actualizacion automatica cada 10 min (systemd timer)"
    fi
}

# ================================================================
#  PASO 10 — Vinculacion de WhatsApp (codigo de emparejamiento)
# ================================================================
link_whatsapp() {
    local port="$1"
    local phone; phone=$(env_get BOT_PHONE)
    if [ -z "$phone" ]; then
        echo ""
        echo -e "${CYAN}  +======================================================+${NC}"
        echo -e "${CYAN}  |   CONFIGURACION WHATSAPP — Numero de telefono       |${NC}"
        echo -e "${CYAN}  +======================================================+${NC}"
        echo "  Incluye codigo de pais sin + ni espacios. Ej Colombia: 573044016277"
        while [ -z "${phone:-}" ] || [ "${#phone}" -lt 10 ]; do
            phone=$(ui_input "Numero de telefono de WhatsApp (con codigo de pais)" "")
            phone="${phone//[^0-9]/}"
            [ "${#phone}" -ge 10 ] || warn "Numero invalido — minimo 10 digitos."
        done
        env_set BOT_PHONE "$phone"
        ok "Numero guardado: $phone"
        as_root rm -rf "${APPDATA_BOT:?}/auth" 2>/dev/null || true
        as_root mkdir -p "$APPDATA_BOT/auth" 2>/dev/null || true
        as_root chown "$SERVICE_USER" "$APPDATA_BOT/auth" 2>/dev/null || true
        systemctl is-active --quiet "$NODE_SVC" 2>/dev/null && as_root systemctl restart "$NODE_SVC" || true
    fi

    wait_server_healthy "$port" 30 || true

    echo ""
    echo -e "${CYAN}  +======================================================+${NC}"
    echo -e "${CYAN}  |   VINCULACION WHATSAPP — sin limite de tiempo        |${NC}"
    echo -e "${CYAN}  |   Cada codigo dura ~60s, aparece uno nuevo si expira |${NC}"
    echo -e "${CYAN}  +======================================================+${NC}"
    info "Esperando codigo de emparejamiento... (Ctrl+C para salir de la espera)"

    local last_code=""
    while true; do
        local log_content
        log_content=$(tail -c 20000 "$LOG_DIR/server.log" 2>/dev/null || as_root journalctl -u "$NODE_SVC" -n 200 --no-pager 2>/dev/null || echo "")
        if echo "$log_content" | grep -q '\[bot\].*Connected'; then
            ok "Bot de WhatsApp CONECTADO exitosamente"
            break
        fi
        local code
        code=$(echo "$log_content" | grep -oE 'Pairing code:\s*[A-Z0-9]{4}-[A-Z0-9]{4}' | tail -1 | grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' || true)
        if [ -n "$code" ] && [ "$code" != "$last_code" ]; then
            last_code="$code"
            echo ""
            echo -e "${GREEN}  +=========================================+${NC}"
            echo -e "${GREEN}  |    CODIGO DE VINCULACION WHATSAPP        |${NC}"
            echo -e "${YELLOW}  |         >>> $code <<<               |${NC}"
            echo -e "${GREEN}  |  WhatsApp > Menu > Dispositivos          |${NC}"
            echo -e "${GREEN}  |  Vincular con numero de telefono         |${NC}"
            echo -e "${GREEN}  +=========================================+${NC}"
        fi
        sleep 3
    done
}

# ================================================================
#  Auditoria de seguridad (para el menu de gestion)
# ================================================================
security_audit() {
    local report="" port; port=$(env_get PORT); port="${port:-$DEFAULT_PORT}"
    report+="Servicio corre como root: "
    if systemctl show "$NODE_SVC" -p User 2>/dev/null | grep -q "User=root\|User=$"; then report+="SI (riesgo alto)\n"; else report+="NO ($(systemctl show "$NODE_SVC" -p User 2>/dev/null | cut -d= -f2))\n"; fi
    report+="Permisos .env: $(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo '?') (recomendado: 600)\n"
    report+="HOST bind: $(env_get HOST) (recomendado: 127.0.0.1, nunca 0.0.0.0)\n"
    report+="Puerto Node ($port) accesible desde afuera: "
    if curl -fsS --connect-timeout 2 "http://0.0.0.0:${port}/health" &>/dev/null; then report+="revisar manualmente\n"; else report+="NO (bien)\n"; fi
    report+="Firewall activo: "
    if has_cmd ufw && as_root ufw status 2>/dev/null | grep -q "Status: active"; then report+="ufw activo\n"
    elif has_cmd firewall-cmd && as_root firewall-cmd --state 2>/dev/null | grep -q running; then report+="firewalld activo\n"
    else report+="no detectado (revisar)\n"; fi
    report+="fail2ban activo: $(systemctl is-active fail2ban 2>/dev/null || echo 'no instalado')\n"
    report+="Servicio Node activo: $(systemctl is-active "$NODE_SVC" 2>/dev/null || echo 'no instalado')\n"
    report+="Tunel Cloudflare activo: $(systemctl is-active "$CF_SVC" 2>/dev/null || echo 'no instalado')\n"
    ui_msg "AUDITORIA DE SEGURIDAD\n\n$(echo -e "$report")"
}

# ================================================================
#  Panel de gestion (menu principal, "GUI")
# ================================================================
status_icon() {
    case "$1" in
        active)  echo "activo" ;;
        failed)  echo "fallo" ;;
        *)       echo "$1" ;;
    esac
}

dashboard() {
    local port; port=$(env_get PORT); port="${port:-$DEFAULT_PORT}"
    local node_status cf_status uptime mem bot_line
    node_status=$(status_icon "$(systemctl is-active "$NODE_SVC" 2>/dev/null || echo 'no-instalado')")
    cf_status=$(status_icon "$(systemctl is-active "$CF_SVC" 2>/dev/null || echo 'no-instalado')")
    uptime=$(systemctl show "$NODE_SVC" -p ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    mem=$(systemctl show "$NODE_SVC" -p MemoryCurrent 2>/dev/null | cut -d= -f2)
    [ -n "$mem" ] && [ "$mem" != "[not set]" ] && mem="$((mem / 1024 / 1024)) MB" || mem="?"
    bot_line=$(curl -fsS --max-time 2 "http://127.0.0.1:${port}/api/bot/status" 2>/dev/null | grep -oE '"ready":(true|false)' || echo "")
    local bot_txt="sin datos (revisa login admin)"
    [[ "$bot_line" == *true*  ]] && bot_txt="WhatsApp conectado"
    [[ "$bot_line" == *false* ]] && bot_txt="WhatsApp reconectando"

    ui_msg "ESTADO DEL SERVIDOR\n\nServidor Node    : $node_status\nTunel Cloudflare : $cf_status\nBot WhatsApp     : $bot_txt\nPuerto (local)   : $port\nMemoria en uso   : $mem\nActivo desde     : ${uptime:-?}\nPublico          : $(load_conf TUNNEL_URL || echo 'no configurado')"
}

management_menu() {
    splash
    while true; do
        local port; port=$(env_get PORT); port="${port:-$DEFAULT_PORT}"
        local status; status=$(status_icon "$(systemctl is-active "$NODE_SVC" 2>/dev/null || echo 'no-instalado')")
        local choice
        choice=$(ui_menu "Servidor: $status   |   Puerto: $port\n\nElige una accion:" \
            D "Dashboard — estado en vivo" \
            1 "Ver estado detallado del servicio" \
            2 "Reiniciar servidor" \
            3 "Detener servidor" \
            4 "Iniciar servidor" \
            5 "Ver logs en vivo (Ctrl+C para salir)" \
            6 "Re-vincular WhatsApp (borra sesion actual)" \
            7 "Cambiar puerto" \
            8 "Regenerar secretos (API_KEY / JWT_SECRET)" \
            9 "Configurar DuckDNS" \
            10 "Configurar dominio propio (nginx + HTTPS)" \
            11 "Auditoria de seguridad" \
            12 "Actualizar codigo (git pull + reinstalar)" \
            13 "Desinstalar todo" \
            0 "Salir")
        case "$choice" in
            D) dashboard ;;
            1) ui_msg "$(systemctl status "$NODE_SVC" --no-pager 2>&1 | head -25)" ;;
            2) as_root systemctl restart "$NODE_SVC" && ok "Reiniciado" ;;
            3) as_root systemctl stop "$NODE_SVC" && ok "Detenido" ;;
            4) as_root systemctl start "$NODE_SVC" && ok "Iniciado" ;;
            5) journalctl -u "$NODE_SVC" -f --no-pager || tail -f "$LOG_DIR/server.log" ;;
            6) env_set BOT_PHONE ""; link_whatsapp "$port" ;;
            7) local np; np=$(ui_input "Nuevo puerto" "$port")
               env_set PORT "$np"; save_conf PORT "$np"; as_root systemctl restart "$NODE_SVC" 2>/dev/null || true
               ok "Puerto actualizado a $np (reinicia el tunel/nginx si aplica)" ;;
            8) env_set API_KEY "$(gen_secret)"; env_set JWT_SECRET "$(gen_secret)"
               as_root systemctl restart "$NODE_SVC" 2>/dev/null || true
               ok "Secretos regenerados — la app movil debera reloguearse" ;;
            9) local sd tk
               sd=$(ui_input "Subdominio DuckDNS (sin .duckdns.org)" "$(load_conf DUCKDNS_SUB)")
               tk=$(ui_input "Token DuckDNS" "")
               save_conf DUCKDNS_SUB "$sd"
               setup_duckdns "$sd" "$tk" ;;
            10) local dm; dm=$(ui_input "Dominio propio (ej: midominio.com)" "")
                [ -n "$dm" ] && setup_nginx_certbot "$port" "$dm" ;;
            11) security_audit ;;
            12) (cd "$PROJ" && git pull --ff-only 2>&1 | tail -10) && install_npm_deps && as_root systemctl restart "$NODE_SVC" && ok "Actualizado" ;;
            13) if ui_yesno "Esto detiene y elimina los servicios systemd instalados (no borra .env ni datos en $APPDATA_BOT). Continuar?"; then
                    uninstall_services
                fi ;;
            0|"") break ;;
        esac
    done
}

uninstall_services() {
    for svc in "$NODE_SVC" "$CF_SVC" duckdns-pedidos-bot.timer duckdns-pedidos-bot.service; do
        as_root systemctl disable --now "$svc" &>/dev/null || true
        as_root rm -f "/etc/systemd/system/${svc}.service" "/etc/systemd/system/${svc}.timer" 2>/dev/null || true
    done
    as_root systemctl daemon-reload 2>/dev/null || true
    ok "Servicios detenidos y eliminados. .env y datos en $APPDATA_BOT se conservan."
}

# ================================================================
#  MAIN
# ================================================================
main_install() {
    splash
    echo ""
    echo -e "${GREEN}${BOLD}  +================================================+${NC}"
    echo -e "${GREEN}${BOLD}  |  CONCENTRADOS MONSERRATH v2.0 — Deploy Linux |${NC}"
    echo -e "${GREEN}${BOLD}  +================================================+${NC}"

    [ -d "$SERVER_DIR" ] || die "No se encontro server/ en $PROJ — ejecuta este script desde la raiz del repo."

    # Ya desplegado -- NO repetir el wizard interactivo completo (no tiene
    # sentido re-preguntar dominio/DuckDNS/telefono de WhatsApp cada vez, y
    # la espera de vinculacion de WhatsApp al final bloquearia el script sin
    # que se note por que en pantalla no cambia nada). Este script SOLO
    # despliega el servidor -- el panel de analisis (dashboard.py) es una
    # herramienta aparte que el usuario abre por su cuenta cuando quiera.
    if systemctl list-unit-files "${NODE_SVC}.service" &>/dev/null 2>&1 \
        && systemctl cat "${NODE_SVC}.service" &>/dev/null 2>&1 \
        && [ -f "$ENV_FILE" ]; then
        info "Ya existe un despliegue de '$NODE_SVC' -- verificando que el servicio este arriba."
        as_root systemctl start "$NODE_SVC" 2>/dev/null || true
        wait_server_healthy "$(env_get PORT)" 20 || true
        ok "Servidor arriba en http://127.0.0.1:$(env_get PORT)/app/"
        info "Panel de analisis: python3 $PROJ/dashboard.py"
        return 0
    fi

    if [ -d "$PROJ/.git" ] && ui_yesno "Actualizar codigo desde git (git pull) antes de desplegar?"; then
        (cd "$PROJ" && git pull --ff-only 2>&1 | tail -10) || warn "git pull fallo — continuando con el codigo actual"
    fi

    install_node
    setup_service_user
    install_npm_deps
    configure_env

    local port; port=$(env_get PORT); port="${port:-$DEFAULT_PORT}"

    install_systemd_service
    wait_server_healthy "$port" 45 || true

    local access_method
    access_method=$(ui_menu "Como quieres exponer el servidor a internet?" \
        1 "Cloudflare Tunnel (recomendado: sin abrir puertos, HTTPS auto)" \
        2 "Dominio propio + nginx + Let's Encrypt (abre 80/443)" \
        3 "Solo red local / VPN (no exponer a internet)")

    case "$access_method" in
        1) install_cloudflared; setup_cloudflared_tunnel "$port"; harden_firewall false ;;
        2) local dm; dm=$(ui_input "Dominio (debe apuntar a la IP de este servidor)" "")
           setup_nginx_certbot "$port" "$dm"; harden_firewall true ;;
        *) harden_firewall false ;;
    esac

    install_fail2ban

    if ui_yesno "Configurar actualizacion automatica de DuckDNS?"; then
        local sd tk
        sd=$(ui_input "Subdominio DuckDNS (sin .duckdns.org)" "")
        tk=$(ui_input "Token DuckDNS" "")
        [ -n "$sd" ] && setup_duckdns "$sd" "$tk"
    fi

    link_whatsapp "$port"

    echo ""
    echo -e "${GREEN}${BOLD}  +======================================================+${NC}"
    echo -e "${GREEN}${BOLD}  |        SISTEMA ACTIVO Y FUNCIONANDO                  |${NC}"
    echo -e "${GREEN}${BOLD}  +======================================================+${NC}"
    echo -e "  Local  : http://127.0.0.1:$port/app/"
    [ -n "$(load_conf TUNNEL_URL)" ] && echo -e "  Publico: $(load_conf TUNNEL_URL)/app/"
    echo -e "  Logs   : $LOG_DIR/ (o: journalctl -u $NODE_SVC -f)"
    echo -e "  Gestion: ./deploy-linux.sh --menu"
    echo -e "  Analisis: python3 $PROJ/dashboard.py"
    echo -e "${GREEN}${BOLD}  +======================================================+${NC}"
    echo ""
}

# NOTA: este script SOLO despliega y gestiona el servidor (systemd, firewall,
# fail2ban, tunel). El panel de analisis (graficas, marca, ventas) vive en
# dashboard.py y es una herramienta aparte -- el usuario la abre directo con
# "python3 dashboard.py" cuando quiera, no se lanza automaticamente desde aqui.

case "${1:-}" in
    --menu)      management_menu ;;
    --uninstall) uninstall_services ;;
    "")          main_install ;;
    *)           die "Uso: $0 [--menu|--uninstall]" ;;
esac
