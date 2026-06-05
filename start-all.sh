#!/bin/bash
# ================================================================
#  start-all.sh — Sistema Concentrados Monserrath
#  Instala dependencias, configura e inicia todo automáticamente
#  Ejecutar: bash start-all.sh
# ================================================================

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME="${HOME:-/home/kali}"
LOG="$PROJ/logs"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "${RED}✗ ERROR:${NC} $1"; exit 1; }
info() { echo -e "  → $1"; }

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   CONCENTRADOS MONSERRATH v2.0             ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
mkdir -p "$LOG"

# ── 1. Node.js via nvm ───────────────────────────────────────
info "Verificando Node.js..."
export NVM_DIR="$HOME/.nvm"
if [ ! -f "$NVM_DIR/nvm.sh" ]; then
  warn "nvm no encontrado. Instalando..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  source "$NVM_DIR/nvm.sh"
  nvm install 20
else
  source "$NVM_DIR/nvm.sh"
  nvm use v20.20.2 --silent 2>/dev/null || nvm use 20 --silent 2>/dev/null || true
fi
node --version &>/dev/null || err "Node.js no disponible"
ok "Node.js: $(node --version)"

# ── 2. Dependencias npm ───────────────────────────────────────
info "Verificando dependencias npm..."
if [ ! -d "$PROJ/server/node_modules/express" ]; then
  warn "Instalando dependencias (puede tardar 2-4 min)..."
  cd "$PROJ/server" && npm install --production --silent \
    || err "npm install falló — revisa conexión a internet"
  ok "Dependencias instaladas"
else
  ok "Dependencias OK"
fi

# ── 3. .env ────────────────────────────────────────────────────
info "Verificando configuración..."
ENV_FILE="$PROJ/server/.env"

if [ ! -f "$ENV_FILE" ]; then
  warn ".env no encontrado — creando configuración automática..."

  # Pedir solo BOT_PHONE (único dato variable por negocio)
  BOT_PHONE_VAL=""
  if [ -t 0 ]; then
    read -rp "  Número WhatsApp del negocio (ej: 573001234567): " BOT_PHONE_VAL
  fi
  [ -z "$BOT_PHONE_VAL" ] && BOT_PHONE_VAL="57"

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
  echo "BOT_PHONE=${BOT_PHONE_VAL}" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok ".env creado (permisos 600)"
fi

set -a; source "$ENV_FILE"; set +a
[ -z "$NGROK_DOMAIN" ]    && err "NGROK_DOMAIN no configurado en .env"
[ -z "$NGROK_AUTHTOKEN" ] && err "NGROK_AUTHTOKEN no configurado en .env"
[ -z "$API_KEY" ]         && err "API_KEY no configurado en .env"
[ -z "$JWT_SECRET" ]      && err "JWT_SECRET no configurado en .env"
ok "Configuración OK"

# ── 4. Base de datos ──────────────────────────────────────────
info "Verificando base de datos..."
DB="$PROJ/server/pedidos.db"
if [ -f "$DB" ]; then
  ok "Base de datos OK ($(du -sh "$DB" | cut -f1))"
  chmod 600 "$DB" 2>/dev/null || true
else
  warn "BD no existe — se crea al iniciar el servidor"
fi

# ── 5. ngrok ─────────────────────────────────────────────────
info "Verificando ngrok..."
export PATH="$PATH:$HOME/bin:/usr/local/bin"
if ! command -v ngrok &>/dev/null; then
  warn "ngrok no encontrado. Descargando..."
  ARCH=$(uname -m)
  [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ] \
    && PKG="ngrok-v3-stable-linux-arm64.tgz" \
    || PKG="ngrok-v3-stable-linux-amd64.tgz"
  mkdir -p "$HOME/bin"
  curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/$PKG" | tar xz -C "$HOME/bin/" \
    || err "No se pudo descargar ngrok"
  ok "ngrok instalado"
fi
ngrok config add-authtoken "$NGROK_AUTHTOKEN" &>/dev/null \
  || err "ngrok: authtoken inválido"
ok "ngrok: $(ngrok version 2>/dev/null | head -1)"

# ── 6. Ollama (LLM) ────────────────────────────────────────────
info "Verificando Ollama..."
if command -v ollama &>/dev/null; then
  if ! pgrep -x ollama &>/dev/null; then
    ollama serve >> "$LOG/ollama.log" 2>&1 &
    sleep 3
  fi
  MODEL="${OLLAMA_MODEL:-llama3.2:1b}"
  if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    warn "Descargando modelo $MODEL (puede tardar 3-5 min)..."
    ollama pull "$MODEL" >> "$LOG/ollama.log" 2>&1
    ok "Modelo $MODEL listo"
  fi
  ok "Ollama activo (modelo: $MODEL)"
else
  warn "Ollama no instalado — parser usará modo reglas (funcional)"
fi

# ── 7. Instalar Ollama si no existe y hay RAM suficiente ──────
RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 1)
if ! command -v ollama &>/dev/null && [ "$RAM_GB" -ge 2 ]; then
  info "Instalando Ollama (RAM disponible: ${RAM_GB}GB)..."
  if curl -fsSL https://ollama.com/install.sh | sh >> "$LOG/ollama.log" 2>&1; then
    ollama serve >> "$LOG/ollama.log" 2>&1 &
    sleep 8
    if ollama pull "${OLLAMA_MODEL:-llama3.2:1b}" >> "$LOG/ollama.log" 2>&1; then
      ok "Ollama instalado"
    else
      warn "Ollama instalado — modelo pendiente: ollama pull ${OLLAMA_MODEL:-llama3.2:1b}"
    fi
  else
    warn "Ollama no pudo instalarse — modo reglas activo"
  fi
fi

# ── 8. Parar instancias previas ───────────────────────────────
info "Limpiando procesos previos..."
pkill -f "node src/index.js" 2>/dev/null || true
pkill -f "ngrok http"        2>/dev/null || true
sleep 1
PORT_PID=$(lsof -ti tcp:${PORT:-3000} 2>/dev/null)
[ -n "$PORT_PID" ] && kill -9 $PORT_PID 2>/dev/null || true
for i in $(seq 1 8); do
  lsof -ti tcp:${PORT:-3000} &>/dev/null || break
  sleep 1
done
lsof -ti tcp:${PORT:-3000} &>/dev/null \
  && err "Puerto ${PORT:-3000} sigue ocupado — mata el proceso manualmente"

# ── 9. Servidor Node.js ───────────────────────────────────────
info "Iniciando servidor..."
cd "$PROJ/server"
nohup node src/index.js >> "$LOG/server.log" 2>&1 &
SERVER_PID=$!

SERVER_OK=0
for i in $(seq 1 25); do
  curl -sf "http://localhost:${PORT:-3000}/health" &>/dev/null && SERVER_OK=1 && break
  sleep 1
done

[ "$SERVER_OK" = "1" ] || {
  tail -10 "$LOG/server.log"
  err "Servidor no respondió en 25s — revisa $LOG/server.log"
}
ok "Servidor activo en :${PORT:-3000} (PID $SERVER_PID)"

# ── 10. Bot WhatsApp ──────────────────────────────────────────
if [ "${BOT_ENABLED:-false}" = "true" ] && [ -n "${BOT_PHONE:-}" ]; then
  ok "Bot WhatsApp: iniciando con teléfono configurado"
  info "Revisa $LOG/server.log para el código de vinculación si es primera vez"
else
  warn "Bot WhatsApp: desactivado (configura BOT_ENABLED=true y BOT_PHONE en .env)"
fi

# ── 11. Túnel ngrok ───────────────────────────────────────────
info "Iniciando túnel ngrok..."
ngrok http "${PORT:-3000}" --url="$NGROK_DOMAIN" --log=stdout >> "$LOG/ngrok.log" 2>&1 &

NGROK_OK=0
for i in $(seq 1 15); do
  curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q "public_url" && NGROK_OK=1 && break
  sleep 1
done
[ "$NGROK_OK" = "1" ] || {
  grep -q "ERR_NGROK_4018\|authentication failed" "$LOG/ngrok.log" 2>/dev/null \
    && err "ngrok: authtoken inválido" \
    || err "ngrok no respondió en 15s — revisa $LOG/ngrok.log"
}
ok "Túnel activo: https://$NGROK_DOMAIN"

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
echo -e "${GREEN}${BOLD}║${NC} Logs: $LOG${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
