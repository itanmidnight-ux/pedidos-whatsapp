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
  cat > "$ENV_FILE" <<'ENVEOF'
PORT=3000
API_KEY=80721f27d4b9e6b1250ccf94f5356f1d9368993ffd0e51d1d9470754e85b9171
JWT_SECRET=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
NGROK_AUTHTOKEN=34G7biMjp4tdGcupxvySfJvYqrQ_6BEU8VntbCjSudDRWntdB
NGROK_DOMAIN=francoise-subhumid-maire.ngrok-free.dev
OLLAMA_MODEL=llama3.2:1b
WORKER_PIN=1234
BOT_ENABLED=true
ENVEOF
  echo "BOT_PHONE=${phone}" >> "$ENV_FILE"
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

# ── 2. Descarga repo si server/ no existe ─────────────────────
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
fi

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
CRITICAL_DEPS="express better-sqlite3 @whiskeysockets/baileys dotenv jsonwebtoken axios pdfkit node-cron bcrypt helmet cors"
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
for key in NGROK_DOMAIN NGROK_AUTHTOKEN API_KEY JWT_SECRET PORT; do
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

# ── 7. ngrok ──────────────────────────────────────────────────
info "Verificando ngrok..."
export PATH="$PATH:$HOME/bin:/usr/local/bin:/snap/bin"
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

# ── 8. Ollama (LLM, opcional) ─────────────────────────────────
info "Verificando Ollama..."
if command -v ollama &>/dev/null; then
  pgrep -x ollama &>/dev/null || ollama serve >> "$LOG/ollama.log" 2>&1 &
  sleep 2
  MODEL="${OLLAMA_MODEL:-llama3.2:1b}"
  ollama list 2>/dev/null | grep -q "$MODEL" || {
    warn "Descargando modelo $MODEL..."
    ollama pull "$MODEL" >> "$LOG/ollama.log" 2>&1 \
      && ok "Modelo $MODEL listo" \
      || warn "Pull falló — parser usará modo reglas"
  }
  ok "Ollama activo ($MODEL)"
else
  RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)
  if [ "$RAM_GB" -ge 2 ]; then
    warn "Instalando Ollama (RAM: ${RAM_GB}GB)..."
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG/ollama.log" 2>&1 && {
      ollama serve >> "$LOG/ollama.log" 2>&1 &
      sleep 8
      ollama pull "${OLLAMA_MODEL:-llama3.2:1b}" >> "$LOG/ollama.log" 2>&1 \
        && ok "Ollama instalado" \
        || warn "Modelo pendiente: ollama pull ${OLLAMA_MODEL:-llama3.2:1b}"
    } || warn "Ollama no instalado — modo reglas activo"
  else
    warn "Ollama no instalado — RAM insuficiente, modo reglas activo"
  fi
fi

# ── 9. Limpiar procesos previos ───────────────────────────────
info "Limpiando procesos previos..."
pkill -f "node src/index.js" 2>/dev/null || true
pkill -f "ngrok http"        2>/dev/null || true
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
    for i in $(seq 1 20); do
      grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null && break
      sleep 2
    done
    grep -q '\[bot\] ✅ Connected' "$LOG/server.log" 2>/dev/null \
      && ok "Bot WhatsApp CONECTADO ✓" \
      || warn "Reconexión en progreso — revisar: tail -f $LOG/server.log"
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

# ── 12. Túnel ngrok ───────────────────────────────────────────
info "Iniciando túnel ngrok..."
ngrok http "${PORT_VAL}" --url="$NGROK_DOMAIN" --log=stdout >> "$LOG/ngrok.log" 2>&1 &
NGROK_PID=$!
echo "$NGROK_PID" > "$PROJ/ngrok.pid"

NGROK_OK=0
for i in $(seq 1 20); do
  curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q '"public_url"' \
    && NGROK_OK=1 && break
  kill -0 "$NGROK_PID" 2>/dev/null || {
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
ok "Túnel activo: https://$NGROK_DOMAIN"

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

# ── Resumen ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║       SISTEMA ACTIVO Y FUNCIONANDO         ║${NC}"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC} App:    https://%-27s${GREEN}${BOLD}║${NC}\n" "$NGROK_DOMAIN/app/"
printf "${GREEN}${BOLD}║${NC} API:    https://%-27s${GREEN}${BOLD}║${NC}\n" "$NGROK_DOMAIN/api/"
printf "${GREEN}${BOLD}║${NC} Estado: https://%-27s${GREEN}${BOLD}║${NC}\n" "$NGROK_DOMAIN/health"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║${NC} Usuarios: jesus | johana | felipe | fabian  ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}║${NC} PIN: 1234 para todos                       ${GREEN}${BOLD}║${NC}"
printf "${GREEN}${BOLD}║${NC} Logs: %-37s${GREEN}${BOLD}║${NC}\n" "$LOG/"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
