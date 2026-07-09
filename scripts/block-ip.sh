#!/usr/bin/env bash
# scripts/block-ip.sh -- bloquea/desbloquea una IP a nivel firewall (iptables).
# Pensado para invocarse SOLO vía sudo NOPASSWD acotado a este script exacto
# (ver setup_ip_block_sudoers en deploy-linux.sh) -- nunca se acepta iptables
# arbitrario desde dashboard.py, solo esta accion validada.
set -euo pipefail

IP="${1:-}"
ACTION="${2:-}"

# Validacion estricta IPv4 -- rechaza cualquier cosa que no sea 4 octetos
# 0-255 separados por puntos. Sin esto, un IP mal formado podria inyectar
# flags extra a iptables (ej. "1.1.1.1 -j ACCEPT" como "IP").
if ! [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "IP invalida: $IP" >&2
    exit 1
fi
for octet in ${IP//./ }; do
    if [ "$octet" -gt 255 ] 2>/dev/null; then
        echo "IP invalida (octeto > 255): $IP" >&2
        exit 1
    fi
done

case "$ACTION" in
    block)
        iptables -C INPUT -s "$IP" -j DROP 2>/dev/null || iptables -I INPUT -s "$IP" -j DROP
        echo "IP $IP bloqueada"
        ;;
    unblock)
        iptables -D INPUT -s "$IP" -j DROP 2>/dev/null || true
        echo "IP $IP desbloqueada"
        ;;
    *)
        echo "Uso: $0 <ip> <block|unblock>" >&2
        exit 1
        ;;
esac
