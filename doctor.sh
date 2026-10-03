#!/usr/bin/env bash
set -uo pipefail

fail=0

ok() { printf '✔ %s\n' "$*"; }
bad() { printf '✘ %s\n' "$*"; fail=1; }

[ -f /etc/arc-host.conf ] && ok "/etc/arc-host.conf" || bad "contrato Arc não registrado"

command -v docker >/dev/null 2>&1 && ok "Docker instalado" || bad "Docker ausente"
docker compose version >/dev/null 2>&1 && ok "Compose disponível" || bad "Compose ausente"
docker info >/dev/null 2>&1 && ok "daemon Docker acessível" || bad "daemon Docker inacessível"

docker network inspect proxy >/dev/null 2>&1 &&
  ok "rede externa proxy" || bad "rede proxy ausente"

for d in /srv/arc/apps /srv/arc/data /srv/arc/backups; do
  [ -d "$d" ] && ok "$d" || bad "$d ausente"
done

if command -v ufw >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    UFW_STATUS="$(ufw status 2>/dev/null || true)"
  elif sudo -n true >/dev/null 2>&1; then
    UFW_STATUS="$(sudo -n ufw status 2>/dev/null || true)"
  else
    UFW_STATUS=""
  fi

  if printf '%s\n' "$UFW_STATUS" | grep -q "Status: active"; then
    ok "UFW ativo"
  elif [ -z "$UFW_STATUS" ]; then
    bad "UFW não pôde ser consultado ao vivo; rode: sudo bash ./doctor.sh"
  else
    bad "UFW inativo"
  fi
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx traefik; then
  ok "Traefik em execução"
else
  echo "• Traefik não está em execução (válido para host sem --edge)"
fi

if [ "$fail" -eq 0 ]; then
  echo
  echo "ARC-READY"
else
  echo
  echo "HOST INCOMPLETO"
fi

exit "$fail"
