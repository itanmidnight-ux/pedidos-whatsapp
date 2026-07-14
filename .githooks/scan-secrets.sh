#!/usr/bin/env bash
# Escanea un diff (stdin, formato `git diff -U0`) buscando dominios reales de
# infraestructura y secretos obvios hardcodeados. Nacio del incidente donde
# 'kali.taileb4183.ts.net' y 'concentrados-monserrath.duckdns.org' quedaron
# escritos a mano en el codigo y se subieron a un repo publico -- ver commit
# "fix(security): quita dominios reales hardcodeados...".
#
# Uso: git diff -U0 <rango> | .githooks/scan-secrets.sh
# Exit 0 = limpio. Exit 1 = encontro algo, imprime detalle.
set -euo pipefail

# Placeholders que SI son validos (los que dejamos nosotros mismos en el
# codigo como ejemplo) -- no deben disparar el bloqueo.
ALLOWLIST_RE='tu-dominio\.com|tu-dominio\.duckdns\.org|midominio\.ts\.net|mi-negocio\.duckdns\.org|ejemplo\.com|example\.com'

PATTERNS=(
    '[a-z0-9-]+\.ts\.net'                         # hostname real de Tailscale
    '[a-z0-9-]+\.duckdns\.org'                    # subdominio real de DuckDNS
    '[a-z0-9-]+\.trycloudflare\.com'              # URL real de tunel Cloudflare
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'AKIA[0-9A-Z]{16}'                            # AWS access key id
    'xox[baprs]-[0-9A-Za-z-]{10,}'                # Slack token
)

found=0
diff_input="$(cat)"

for pat in "${PATTERNS[@]}"; do
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Solo lineas agregadas (+), no las de contexto/borradas ni el header +++
        case "$line" in
            '+++'*) continue ;;
        esac
        match=$(echo "$line" | grep -oE -- "$pat" || true)
        [ -z "$match" ] && continue
        if echo "$match" | grep -qiE "$ALLOWLIST_RE"; then continue; fi
        echo "BLOQUEADO: patron '$pat' -> '$match'"
        echo "  linea: ${line#+}"
        found=1
    done < <(echo "$diff_input" | grep -E '^\+[^+]')
done

if [ "$found" = "1" ]; then
    echo ""
    echo "Commit/push bloqueado: parece un dominio real o secreto hardcodeado."
    echo "Si es infraestructura real, muevelo a .env / settings (DB), no al codigo."
    echo "Si es un placeholder legitimo nuevo, agregalo a ALLOWLIST_RE en"
    echo ".githooks/scan-secrets.sh."
    exit 1
fi
exit 0
