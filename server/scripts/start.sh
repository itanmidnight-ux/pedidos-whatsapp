#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use v20.20.2 --silent 2>/dev/null

cd /home/kali/Jesus/server
source .env

node src/index.js >> /home/kali/Jesus/logs/server.log 2>&1 &
echo "Servidor iniciado (puerto $PORT)"

ngrok http $PORT --domain=$NGROK_DOMAIN --log=stdout >> /home/kali/Jesus/logs/ngrok.log 2>&1 &
echo "ngrok iniciado → https://$NGROK_DOMAIN"
