#!/bin/bash
# ================================================================
#  start-all.sh — Concentrados Monserrath
#  Instala, configura e inicia todo el sistema automáticamente
#  Uso: bash start-all.sh
# ================================================================

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME="${HOME:-/home/kali}"
LOG="$PROJ/logs"
ENV_FILE="$PROJ/server/.env"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
TUNNEL_TYPE="${TUNNEL_TYPE:-ngrok}"  # ngrok | cloudflared

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "${RED}✗ ERROR:${NC} $1" >&2; exit 1; }
info() { echo -e "  → $1"; }

_ask_phone() {
  local phone=""
  if [ -t 0 ]; then
    while true; do
      read -rp "  Número WhatsApp del negocio (ej: 573001234567): " phone
      phone=$(echo "$phone" | tr -dc '0-9')
      [ "${#phone}" -ge 10 ] && { echo "$phone"; return 0; }
      [ -z "$phone" ]        && { echo ""; return 0; }
      warn "  Número inválido — mínimo 10 dígitos, solo números"
    done
  fi
  echo ""
}

_write_env() {
  local phone="$1"
  mkdir -p "$(dirname "$ENV_FILE")"
  # Generate cryptographically random secrets for this installation
  local jwt_secret api_key
  jwt_secret=$(openssl rand -hex 32 2>/dev/null \
    || od -A n -t x1 /dev/urandom 2>/dev/null | tr -dc 'a-f0-9' | head -c 64 \
    || echo "CHANGE_ME_$(date +%s%N | sha256sum 2>/dev/null | head -c 48)")
  api_key=$(openssl rand -hex 32 2>/dev/null \
    || od -A n -t x1 /dev/urandom 2>/dev/null | tr -dc 'a-f0-9' | head -c 64 \
    || echo "CHANGE_ME_$(date +%s%N | sha256sum 2>/dev/null | head -c 48)")
  cat > "$ENV_FILE" <<ENVEOF
PORT=3000
API_KEY=${api_key}
JWT_SECRET=${jwt_secret}
NGROK_AUTHTOKEN=34G7biMjp4tdGcupxvySfJvYqrQ_6BEU8VntbCjSudDRWntdB
NGROK_DOMAIN=francoise-subhumid-maire.ngrok-free.dev
BOT_ENABLED=true
ENVEOF
  printf 'BOT_PHONE=%s\n' "$phone" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   CONCENTRADOS MONSERRATH v2.0             ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
mkdir -p "$LOG"

# ── 0. Herramientas del sistema ───────────────────────────────
info "Verificando herramientas del sistema..."
MISSING=""
for tool in curl unzip git lsof tar; do
  command -v "$tool" &>/dev/null || MISSING="$MISSING $tool"
done
if [ -n "$MISSING" ]; then
  warn "Faltan:$MISSING — instalando..."
  if command -v apt-get &>/dev/null; then
    apt-get update -qq 2>/dev/null
    apt-get install -y $MISSING -qq 2>/dev/null \
      || err "No se pudieron instalar:$MISSING (ejecutar con sudo)"
  elif command -v apk &>/dev/null; then
    apk add --no-cache $MISSING 2>/dev/null \
      || err "No se pudieron instalar:$MISSING"
  else
    err "Instalar manualmente:$MISSING"
  fi
fi
ok "Herramientas del sistema OK"

# ── 0b. Eliminar Ollama (reemplazado por NLP.js) ──────────────
if command -v ollama &>/dev/null || [ -d "$HOME/.ollama" ]; then
  warn "Ollama detectado — eliminando para liberar espacio (reemplazado por NLP.js)..."
  pkill -f ollama 2>/dev/null || true
  sleep 1
  for _bin in /usr/local/bin/ollama /usr/bin/ollama "$HOME/bin/ollama" /snap/bin/ollama; do
    [ -f "$_bin" ] && { rm -f "$_bin" 2>/dev/null || sudo rm -f "$_bin" 2>/dev/null || true; }
  done
  if [ -d "$HOME/.ollama" ]; then
    OLLAMA_SIZE=$(du -sh "$HOME/.ollama" 2>/dev/null | cut -f1 || echo "?")
    rm -rf "$HOME/.ollama"
    ok "Ollama eliminado — espacio liberado: ${OLLAMA_SIZE}"
  else
    ok "Ollama eliminado del sistema"
  fi
fi

# ── 1. Número WhatsApp (input temprano, antes de instalaciones) ──
COLLECTED_PHONE=""
if [ ! -f "$ENV_FILE" ]; then
  echo ""
  info "Primera ejecución — ingresa el número WhatsApp del negocio:"
  COLLECTED_PHONE=$(_ask_phone)
  echo ""
else
  set -a; source "$ENV_FILE" 2>/dev/null; set +a
  BOT_PHONE_CHECK=$(echo "${BOT_PHONE:-}" | tr -dc '0-9')
  if [ "${#BOT_PHONE_CHECK}" -lt 10 ]; then
    warn "BOT_PHONE no configurado o inválido"
    info "Ingresa el número WhatsApp del negocio:"
    COLLECTED_PHONE=$(_ask_phone)
    echo ""
  fi
fi

# ── 2. Descarga o actualiza repositorio ──────────────────────
if [ ! -d "$PROJ/server" ]; then
  warn "Directorio server/ no encontrado — descargando repositorio..."
  TMP=$(mktemp -d)
  curl -fsSL \
    "https://github.com/itanmidnight-ux/pedidos-whatsapp/archive/refs/heads/main.zip" \
    -o "$TMP/repo.zip" \
    || err "No se pudo descargar repositorio — verifica conexión"
  unzip -q "$TMP/repo.zip" -d "$TMP/"
  cp -r "$TMP/pedidos-whatsapp-main/server" "$PROJ/"
  rm -rf "$TMP"
  ok "Repositorio descargado"
else
  # Pull latest code so all bug fixes are applied automatically
  if [ -d "$PROJ/.git" ] && command -v git &>/dev/null; then
    git -C "$PROJ" pull --ff-only --quiet origin main 2>/dev/null \
      && ok "Código actualizado desde GitHub" \
      || warn "git pull omitido (sin conexión o cambios locales) — usando código actual"
  fi
fi

# ── 2b. Directorios de media (se crean antes de arrancar servidor) ──
mkdir -p "$HOME/pedidos-bot/media"
mkdir -p "$HOME/pedidos-bot/product-images"
mkdir -p "$HOME/pedidos-bot/estados"
mkdir -p "$HOME/pedidos-bot/auth"
ok "Directorios de media y auth listos"

# ── 3. Node.js via nvm ────────────────────────────────────────
info "Verificando Node.js..."
export NVM_DIR="$HOME/.nvm"
if [ ! -f "$NVM_DIR/nvm.sh" ]; then
  warn "nvm no encontrado. Instalando..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
    || err "No se pudo instalar nvm"
  source "$NVM_DIR/nvm.sh"
  nvm install 20 || err "No se pudo instalar Node.js 20"
else
  source "$NVM_DIR/nvm.sh"
  nvm use v20.20.2 --silent 2>/dev/null \
    || nvm use 20 --silent 2>/dev/null \
    || nvm install 20 --silent 2>/dev/null \
    || true
fi
node --version &>/dev/null || err "Node.js no disponible — instalar manualmente"
ok "Node.js: $(node --version)"

# ── 4. Dependencias npm ───────────────────────────────────────
info "Verificando dependencias npm..."
CRITICAL_DEPS="express better-sqlite3 @whiskeysockets/baileys dotenv jsonwebtoken axios pdfkit node-cron bcrypt helmet cors @nlpjs/basic multer express-rate-limit"
NEEDS_INSTALL=0
for dep in $CRITICAL_DEPS; do
  [ ! -d "$PROJ/server/node_modules/$dep" ] && { NEEDS_INSTALL=1; break; }
done
if [ "$NEEDS_INSTALL" = "1" ]; then
  warn "Instalando dependencias npm (3-5 min)..."
  cd "$PROJ/server"
  npm install --production --silent 2>>"$LOG/npm.log" \
    || { warn "Reintentando sin cache..."; npm install --production --prefer-offline 2>>"$LOG/npm.log" \
    || err "npm install falló — revisa $LOG/npm.log"; }
  # Verify all critical deps installed
  for dep in $CRITICAL_DEPS; do
    [ ! -d "$PROJ/server/node_modules/$dep" ] \
      && err "Dependencia '$dep' no instalada — revisa $LOG/npm.log"
  done
  ok "Dependencias instaladas"
else
  ok "Dependencias OK"
fi
cd "$PROJ"

# ── 5. Configuración .env ─────────────────────────────────────
info "Verificando configuración..."
if [ ! -f "$ENV_FILE" ]; then
  _write_env "$COLLECTED_PHONE"
  ok ".env creado"
elif [ -n "$COLLECTED_PHONE" ]; then
  # Update BOT_PHONE in existing .env
  if grep -q '^BOT_PHONE=' "$ENV_FILE"; then
    sed -i "s/^BOT_PHONE=.*/BOT_PHONE=${COLLECTED_PHONE}/" "$ENV_FILE"
  else
    echo "BOT_PHONE=${COLLECTED_PHONE}" >> "$ENV_FILE"
  fi
  ok "BOT_PHONE actualizado: ${COLLECTED_PHONE}"
fi

# Source final .env
set -a; source "$ENV_FILE"; set +a

# Validate required keys
REQUIRED_KEYS="API_KEY JWT_SECRET PORT"
[ "$TUNNEL_TYPE" = "ngrok" ] && REQUIRED_KEYS="$REQUIRED_KEYS NGROK_DOMAIN NGROK_AUTHTOKEN"
for key in $REQUIRED_KEYS; do
  eval "val=\${${key}:-}"
  [ -z "$val" ] && err "$key no configurado en .env"
done
PORT_VAL="${PORT:-3000}"

# Final BOT_PHONE check
BOT_PHONE_CLEAN=$(echo "${BOT_PHONE:-}" | tr -dc '0-9')
if [ "${#BOT_PHONE_CLEAN}" -lt 10 ]; then
  warn "BOT_PHONE no válido — bot WhatsApp desactivado esta sesión"
  export BOT_ENABLED=false
fi
ok "Configuración OK"

# ── 6. Base de datos ──────────────────────────────────────────
info "Verificando base de datos..."
DB="$PROJ/server/pedidos.db"
if [ -f "$DB" ]; then
  ok "Base de datos OK ($(du -sh "$DB" | cut -f1))"
  chmod 600 "$DB" 2>/dev/null || true
else
  warn "BD no existe — se crea al primer inicio"
fi

# ── 7. Túnel (ngrok o cloudflared) ────────────────────────────
export PATH="$PATH:$HOME/bin:/usr/local/bin:/snap/bin"

if [ "$TUNNEL_TYPE" = "cloudflared" ]; then
  info "Verificando cloudflared..."
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared no encontrado. Instalando..."
    ARCH=$(uname -m)
    case "$ARCH" in
      aarch64|arm64) CF_PKG="cloudflared-linux-arm64" ;;
      armv7l)        CF_PKG="cloudflared-linux-arm" ;;
      *)             CF_PKG="cloudflared-linux-amd64" ;;
    esac
    mkdir -p "$HOME/bin"
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_PKG}" \
      -o "$HOME/bin/cloudflared" \
      || err "No se pudo descargar cloudflared"
    chmod +x "$HOME/bin/cloudflared"
    ok "cloudflared instalado"
  fi
  ok "cloudflared: $(cloudflared --version 2>/dev/null | head -1)"
else
  info "Verificando ngrok..."
  if ! command -v ngrok &>/dev/null; then
    warn "ngrok no encontrado. Descargando..."
    ARCH=$(uname -m)
    case "$ARCH" in
      aarch64|arm64) NGROK_PKG="ngrok-v3-stable-linux-arm64.tgz" ;;
      armv7l)        NGROK_PKG="ngrok-v3-stable-linux-arm.tgz" ;;
      *)             NGROK_PKG="ngrok-v3-stable-linux-amd64.tgz" ;;
    esac
    mkdir -p "$HOME/bin"
    curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/$NGROK_PKG" \
      | tar xz -C "$HOME/bin/" \
      || err "No se pudo descargar ngrok"
    chmod +x "$HOME/bin/ngrok"
    ok "ngrok instalado"
  fi
  ngrok config add-authtoken "$NGROK_AUTHTOKEN" &>/dev/null \
    || err "ngrok authtoken inválido — verifica NGROK_AUTHTOKEN en .env"
  ok "ngrok: $(ngrok version 2>/dev/null | head -1)"
fi

# ── 8. Parser NLP (NLP.js — entrenado automáticamente al iniciar servidor) ──
ok "Parser NLP.js activo — entrenamiento automático con productos de DB"

# ── 9. Limpiar procesos previos ───────────────────────────────
info "Limpiando procesos previos..."
pkill -f "node src/index.js" 2>/dev/null || true
if [ "$TUNNEL_TYPE" = "cloudflared" ]; then
  pkill -f "cloudflared tunnel" 2>/dev/null || true
else
  pkill -f "ngrok http" 2>/dev/null || true
fi
sleep 1
PORT_PID=$(lsof -ti "tcp:${PORT_VAL}" 2>/dev/null || true)
[ -n "$PORT_PID" ] && kill -9 $PORT_PID 2>/dev/null || true
for i in $(seq 1 10); do
  lsof -ti "tcp:${PORT_VAL}" &>/dev/null || break
  sleep 1
done
lsof -ti "tcp:${PORT_VAL}" &>/dev/null \
  && err "Puerto ${PORT_VAL} sigue ocupado: lsof -ti tcp:${PORT_VAL} | xargs kill -9"
ok "Procesos limpios"

# ── 10. Servidor Node.js ──────────────────────────────────────
info "Iniciando servidor..."
cd "$PROJ/server"
: > "$LOG/server.log"
nohup node src/index.js >> "$LOG/server.log" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PROJ/server.pid"

# Crash-early check
sleep 2
kill -0 "$SERVER_PID" 2>/dev/null || {
  tail -20 "$LOG/server.log" >&2
  err "Servidor falló al iniciar — revisa $LOG/server.log"
}

SERVER_OK=0
for i in $(seq 1 30); do
  curl -sf "http://localhost:${PORT_VAL}/health" &>/dev/null && SERVER_OK=1 && break
  kill -0 "$SERVER_PID" 2>/dev/null || {
    tail -10 "$LOG/server.log" >&2
    err "Servidor murió durante startup — revisa $LOG/server.log"
  }
  sleep 1
done
[ "$SERVER_OK" = "1" ] || {
  tail -15 "$LOG/server.log" >&2
  err "Servidor no respondió en 30s — revisa $LOG/server.log"
}
ok "Servidor activo en :${PORT_VAL} (PID $SERVER_PID)"
cd "$PROJ"

# ── 11. Bot WhatsApp ──────────────────────────────────────────
if [ "${BOT_ENABLED:-false}" = "true" ] && [ "${#BOT_PHONE_CLEAN}" -ge 10 ]; then
  AUTH_DIR="${HOME}/pedidos-bot/auth"
  mkdir -p "$AUTH_DIR"

  # Detect valid session (exists + no zero-byte files = not corrupted)
  SESSION_VALID=0
  if [ -n "$(ls -A "$AUTH_DIR" 2>/dev/null)" ]; then
    ZERO_FILES=$(find "$AUTH_DIR" -size 0 2>/dev/null | wc -l)
    [ "${ZERO_FILES:-0}" -eq 0 ] && SESSION_VALID=1
  fi

  if [ "$SESSION_VALID" = "1" ]; then
    ok "Bot WhatsApp: sesión guardada — reconectando..."
    # Wait for Connected OR pairing code (session may have been revoked manually)
    WA_CONNECTED=0
    PAIR_CODE=""
    for i in $(seq 1 50); do
      if grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null; then
        WA_CONNECTED=1; break
      fi
      PAIR_CODE=$(grep -o 'Pairing code: [A-Z0-9-]*' "$LOG/server.log" 2>/dev/null \
        | tail -1 | sed 's/Pairing code: //')
      [ -n "$PAIR_CODE" ] && break
      sleep 2
    done

    if [ "$WA_CONNECTED" = "1" ]; then
      ok "Bot WhatsApp CONECTADO ✓"
    elif [ -n "$PAIR_CODE" ]; then
      # Session was revoked — show pairing code
      warn "Sesión revocada — se requiere nueva vinculación"
      echo ""
      echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
      echo -e "${GREEN}${BOLD}║   CÓDIGO DE VINCULACIÓN WHATSAPP             ║${NC}"
      echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
      echo -e "${GREEN}${BOLD}║${NC}   ${BOLD}${PAIR_CODE}${NC}$(printf '%*s' $((38 - ${#PAIR_CODE})) '')${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 1. Abre WhatsApp en tu teléfono              ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 2. Menú (⋮) → Dispositivos vinculados        ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 3. Vincular un dispositivo                   ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 4. Vincular con número de teléfono           ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 5. Ingresa el código de arriba               ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
      echo ""
      info "Esperando confirmación de conexión (máx 120s)..."
      for i in $(seq 1 60); do
        grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null && break
        sleep 2
      done
      if grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null; then
        ok "Bot WhatsApp CONECTADO ✓"
      else
        warn "Sin confirmación en 120s — verifica el código en WhatsApp"
        warn "El sistema continúa — bot reintenta automáticamente"
      fi
    else
      warn "Reconexión en progreso — revisar: tail -f $LOG/server.log"
    fi
  else
    # Remove corrupted session if present
    [ -n "$(ls -A "$AUTH_DIR" 2>/dev/null)" ] && {
      warn "Sesión corrupta — limpiando para re-vincular..."
      rm -rf "${AUTH_DIR:?}"/*
    }

    ok "Bot WhatsApp: esperando código de vinculación..."
    echo ""
    PAIR_CODE=""
    for i in $(seq 1 40); do
      PAIR_CODE=$(grep -o 'Pairing code: [A-Z0-9-]*' "$LOG/server.log" 2>/dev/null \
        | tail -1 | sed 's/Pairing code: //')
      [ -n "$PAIR_CODE" ] && break
      kill -0 "$SERVER_PID" 2>/dev/null \
        || err "Servidor murió esperando código WhatsApp — revisa $LOG/server.log"
      sleep 2
    done

    if [ -n "$PAIR_CODE" ]; then
      echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
      echo -e "${GREEN}${BOLD}║   CÓDIGO DE VINCULACIÓN WHATSAPP             ║${NC}"
      echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
      echo -e "${GREEN}${BOLD}║${NC}   ${BOLD}${PAIR_CODE}${NC}$(printf '%*s' $((38 - ${#PAIR_CODE})) '')${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════╣${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 1. Abre WhatsApp en tu teléfono              ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 2. Menú (⋮) → Dispositivos vinculados        ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 3. Vincular un dispositivo                   ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 4. Vincular con número de teléfono           ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}║${NC} 5. Ingresa el código de arriba               ${GREEN}${BOLD}║${NC}"
      echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
      echo ""
      info "Esperando confirmación de conexión (máx 120s)..."
      for i in $(seq 1 60); do
        grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null && break
        sleep 2
      done
      if grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null; then
        ok "Bot WhatsApp CONECTADO ✓"
      else
        warn "Sin confirmación en 120s — verifica el código en WhatsApp"
        warn "El sistema continúa — bot reintenta automáticamente (máx 10 intentos)"
      fi
    else
      warn "Código no apareció en 80s — revisa $LOG/server.log"
      warn "El sistema continúa — bot reintenta automáticamente"
    fi
  fi
else
  warn "Bot WhatsApp desactivado — configura BOT_PHONE con número válido en .env"
fi

# ── 12. Túnel ─────────────────────────────────────────────────
info "Iniciando túnel ($TUNNEL_TYPE)..."
TUNNEL_URL=""

if [ "$TUNNEL_TYPE" = "cloudflared" ]; then
  : > "$LOG/tunnel.log"
  # Named tunnel (si CF_TUNNEL_NAME está configurado) o quick tunnel
  if [ -n "${CF_TUNNEL_NAME:-}" ]; then
    cloudflared tunnel run "$CF_TUNNEL_NAME" >> "$LOG/tunnel.log" 2>&1 &
  else
    cloudflared tunnel --url "http://localhost:${PORT_VAL}" --no-autoupdate >> "$LOG/tunnel.log" 2>&1 &
  fi
  TUNNEL_PID=$!
  echo "$TUNNEL_PID" > "$PROJ/tunnel.pid"

  TUNNEL_OK=0
  for i in $(seq 1 30); do
    TUNNEL_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$LOG/tunnel.log" 2>/dev/null | tail -1)
    [ -n "$TUNNEL_URL" ] && TUNNEL_OK=1 && break
    # Named tunnel
    grep -q 'Registered tunnel connection' "$LOG/tunnel.log" 2>/dev/null && TUNNEL_OK=1 && break
    kill -0 "$TUNNEL_PID" 2>/dev/null || { tail -5 "$LOG/tunnel.log" >&2; err "cloudflared murió al iniciar"; }
    sleep 2
  done
  [ "$TUNNEL_OK" = "1" ] || { tail -5 "$LOG/tunnel.log" >&2; err "cloudflared no respondió en 60s"; }
  [ -z "$TUNNEL_URL" ] && TUNNEL_URL="${CF_TUNNEL_NAME:-cloudflared-tunnel}"
  ok "Túnel cloudflared activo: $TUNNEL_URL"

else
  # ngrok (default)
  : > "$LOG/ngrok.log"
  ngrok http "${PORT_VAL}" --url="$NGROK_DOMAIN" --log=stdout >> "$LOG/ngrok.log" 2>&1 &
  TUNNEL_PID=$!
  echo "$TUNNEL_PID" > "$PROJ/tunnel.pid"
  # Keep legacy ngrok.pid for compatibility
  echo "$TUNNEL_PID" > "$PROJ/ngrok.pid"

  NGROK_OK=0
  for i in $(seq 1 20); do
    curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q '"public_url"' \
      && NGROK_OK=1 && break
    kill -0 "$TUNNEL_PID" 2>/dev/null || {
      tail -5 "$LOG/ngrok.log" >&2
      err "ngrok murió al iniciar — revisa $LOG/ngrok.log"
    }
    sleep 1
  done
  [ "$NGROK_OK" = "1" ] || {
    grep -qE "ERR_NGROK_4018|authentication failed" "$LOG/ngrok.log" 2>/dev/null \
      && err "ngrok: authtoken inválido — verifica NGROK_AUTHTOKEN en .env" \
      || { tail -5 "$LOG/ngrok.log" >&2; err "ngrok no respondió en 20s — revisa $LOG/ngrok.log"; }
  }
  TUNNEL_URL="https://$NGROK_DOMAIN"
  ok "Túnel ngrok activo: $TUNNEL_URL"
fi

# ── 13. Servicio systemd (persistencia en reboot) ─────────────
SVC="pedidos-monserrath"
SVC_FILE="/etc/systemd/system/${SVC}.service"
if command -v systemctl &>/dev/null && [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; then
  if [ ! -f "$SVC_FILE" ]; then
    info "Configurando servicio systemd (auto-inicio en reboot)..."
    NODE_BIN=$(command -v node)
    SVC_DEF="[Unit]
Description=Pedidos Concentrados Monserrath
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${PROJ}/server
ExecStart=${NODE_BIN} src/index.js
Restart=always
RestartSec=10
StartLimitIntervalSec=120
StartLimitBurst=5
StandardOutput=append:${LOG}/server.log
StandardError=append:${LOG}/server.log
EnvironmentFile=${PROJ}/server/.env

[Install]
WantedBy=multi-user.target"
    if [ "$(id -u)" = "0" ]; then
      printf '%s\n' "$SVC_DEF" > "$SVC_FILE"
      systemctl daemon-reload 2>/dev/null && systemctl enable "$SVC" 2>/dev/null \
        && ok "Servicio systemd: ${SVC} habilitado" \
        || warn "systemctl enable falló — ver: journalctl -u ${SVC}"
    elif command -v sudo &>/dev/null; then
      printf '%s\n' "$SVC_DEF" | sudo tee "$SVC_FILE" > /dev/null
      sudo systemctl daemon-reload 2>/dev/null && sudo systemctl enable "$SVC" 2>/dev/null \
        && ok "Servicio systemd: ${SVC} habilitado" \
        || warn "systemctl enable falló — ejecutar con sudo para persistencia"
    else
      warn "Sin root/sudo — systemd no configurado. Ejecutar con sudo para persistencia."
    fi
  else
    ok "Servicio systemd: ${SVC} ya configurado"
  fi
else
  warn "systemd no disponible — reiniciar con: bash start-all.sh"
fi

# ── 14. NLP health check ─────────────────────────────────────
info "Verificando parser NLP..."
NLP_OK=0
for i in $(seq 1 10); do
  HEALTH=$(curl -sf "http://localhost:${PORT_VAL}/health" 2>/dev/null)
  if echo "$HEALTH" | grep -q '"status":"ok"'; then
    NLP_OK=1; break
  fi
  sleep 1
done
if [ "$NLP_OK" = "1" ]; then
  ok "NLP.js activo — parseador de pedidos en español listo"
else
  warn "NLP health check no respondió — revisar: tail -f $LOG/server.log"
fi

# ── 15. Watchdog — reinicio automático servidor + túnel ───────
(
  while true; do
    sleep 30
    # Servidor
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "[watchdog] $(date '+%H:%M:%S') Servidor caído — reiniciando..." >> "$LOG/server.log"
      cd "$PROJ/server"
      nohup node src/index.js >> "$LOG/server.log" 2>&1 &
      SERVER_PID=$!
      echo "$SERVER_PID" > "$PROJ/server.pid"
    fi
    # Túnel
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
      echo "[watchdog] $(date '+%H:%M:%S') Túnel caído — reiniciando..." >> "$LOG/tunnel.log"
      if [ "$TUNNEL_TYPE" = "cloudflared" ]; then
        if [ -n "${CF_TUNNEL_NAME:-}" ]; then
          cloudflared tunnel run "$CF_TUNNEL_NAME" >> "$LOG/tunnel.log" 2>&1 &
        else
          cloudflared tunnel --url "http://localhost:${PORT_VAL}" --no-autoupdate >> "$LOG/tunnel.log" 2>&1 &
        fi
      else
        ngrok http "${PORT_VAL}" --url="$NGROK_DOMAIN" --log=stdout >> "$LOG/ngrok.log" 2>&1 &
      fi
      TUNNEL_PID=$!
      echo "$TUNNEL_PID" > "$PROJ/tunnel.pid"
    fi
    # WhatsApp reconnection is managed automatically by waBot.js — no watchdog intervention needed
  done
) &
echo $! > "$PROJ/watchdog.pid"
ok "Watchdog activo (servidor + túnel + WA, PID $(cat "$PROJ/watchdog.pid"))"

# ── Resumen ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║       SISTEMA ACTIVO Y FUNCIONANDO         ║${NC}"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC} App:    %-36s${GREEN}${BOLD}║${NC}\n" "${TUNNEL_URL}/app/"
printf "${GREEN}${BOLD}║${NC} API:    %-36s${GREEN}${BOLD}║${NC}\n" "${TUNNEL_URL}/api/"
printf "${GREEN}${BOLD}║${NC} Estado: %-36s${GREEN}${BOLD}║${NC}\n" "${TUNNEL_URL}/health"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║${NC} Roles: admin | worker | client             ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}║${NC} Auth: contraseña (no PIN) — mín 1 char     ${GREEN}${BOLD}║${NC}"
printf "${GREEN}${BOLD}║${NC} Túnel: %-36s${GREEN}${BOLD}║${NC}\n" "$TUNNEL_TYPE"
printf "${GREEN}${BOLD}║${NC} Logs: %-37s${GREEN}${BOLD}║${NC}\n" "$LOG/"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
