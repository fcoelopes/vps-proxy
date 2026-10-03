#!/usr/bin/env bash
set -euo pipefail

PROVIDER="generic"
ARC_USER=""
SSH_PORT="22"
SWAP_SIZE="2G"
ENABLE_FIREWALL="true"
ENABLE_EDGE="false"
DASHBOARD_DOMAIN=""
ACME_EMAIL=""

usage() {
  cat <<'EOF'
Uso:
  sudo bash ./bootstrap.sh [opções]

Opções:
  --provider aws|contabo|hetzner|oci|generic
  --user USUARIO
  --ssh-port PORTA
  --swap TAMANHO            default: 2G; use 0 para não criar
  --no-firewall
  --edge                    prepara e sobe Traefik
  --dashboard-domain HOST   ex: traefik.exemplo.com
  --acme-email EMAIL
  -h, --help

Exemplo:
  sudo bash ./bootstrap.sh --provider contabo --user arc \
    --edge --dashboard-domain traefik.exemplo.com --acme-email ops@exemplo.com
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --user) ARC_USER="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --swap) SWAP_SIZE="$2"; shift 2 ;;
    --no-firewall) ENABLE_FIREWALL="false"; shift ;;
    --edge) ENABLE_EDGE="true"; shift ;;
    --dashboard-domain) DASHBOARD_DOMAIN="$2"; shift 2 ;;
    --acme-email) ACME_EMAIL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

case "$PROVIDER" in
  aws|contabo|hetzner|oci|generic) ;;
  *) echo "Provider inválido: $PROVIDER" >&2; exit 2 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute como root/sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$ARC_USER" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    ARC_USER="$SUDO_USER"
  else
    ARC_USER="arc"
  fi
fi

. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *)
    echo "Distribuição não suportada: ${ID:-desconhecida}. Use Ubuntu/Debian." >&2
    exit 1
    ;;
esac

echo "▶ Arc host bootstrap"
echo "  provider=$PROVIDER user=$ARC_USER distro=$ID ${VERSION_CODENAME:-}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg git ufw unattended-upgrades apache2-utils

if ! id "$ARC_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$ARC_USER"
  echo "✔ usuário $ARC_USER criado"
fi

usermod -aG sudo "$ARC_USER"

# Em imagens cloud o acesso inicial costuma estar em root/ubuntu/debian.
# Copia as chaves somente se o usuário Arc ainda não tiver authorized_keys.
SOURCE_HOME=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  SOURCE_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
elif [ -f /root/.ssh/authorized_keys ]; then
  SOURCE_HOME="/root"
fi

TARGET_HOME="$(getent passwd "$ARC_USER" | cut -d: -f6)"
if [ -n "$SOURCE_HOME" ] && [ -f "$SOURCE_HOME/.ssh/authorized_keys" ] &&
   [ ! -f "$TARGET_HOME/.ssh/authorized_keys" ]; then
  install -d -m 700 -o "$ARC_USER" -g "$ARC_USER" "$TARGET_HOME/.ssh"
  install -m 600 -o "$ARC_USER" -g "$ARC_USER"     "$SOURCE_HOME/.ssh/authorized_keys" "$TARGET_HOME/.ssh/authorized_keys"
  echo "✔ chave(s) SSH copiadas para $ARC_USER"
fi

if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" |
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID ${VERSION_CODENAME} stable"     > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io     docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker
usermod -aG docker "$ARC_USER"

if [ ! -f /etc/docker/daemon.json ]; then
  cat >/etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
JSON
  systemctl restart docker
  echo "✔ rotação de logs Docker configurada"
else
  echo "• /etc/docker/daemon.json já existe; não sobrescrito"
fi

if [ "$SWAP_SIZE" != "0" ] && ! swapon --show --noheadings | grep -q .; then
  if [ ! -f /swapfile ]; then
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile
  grep -qE '^/swapfile\s' /etc/fstab ||
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "✔ swap $SWAP_SIZE ativa"
fi

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

if [ "$ENABLE_FIREWALL" = "true" ]; then
  ufw allow "${SSH_PORT}/tcp" >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  echo "✔ UFW: SSH/$SSH_PORT + 80 + 443"
fi

install -d -m 0755 -o "$ARC_USER" -g "$ARC_USER"   /srv/arc /srv/arc/apps /srv/arc/data /srv/arc/backups

docker network inspect proxy >/dev/null 2>&1 || docker network create proxy >/dev/null

cat >/etc/arc-host.conf <<EOF
ARC_HOST_VERSION=1
ARC_PROVIDER=$PROVIDER
ARC_USER=$ARC_USER
ARC_ROOT=/srv/arc
ARC_PROXY_NETWORK=proxy
EOF

echo "✔ contrato Arc-ready aplicado"

if [ "$ENABLE_EDGE" = "true" ]; then
  cd "$SCRIPT_DIR"

  if [ -z "$DASHBOARD_DOMAIN" ] || [ -z "$ACME_EMAIL" ]; then
    echo "✘ --edge exige --dashboard-domain e --acme-email" >&2
    exit 2
  fi

  cat >.env <<EOF
TRAEFIK_DASHBOARD_DOMAIN=$DASHBOARD_DOMAIN
ACME_EMAIL=$ACME_EMAIL
EOF
  chmod 600 .env

  touch acme.json
  chmod 600 acme.json
  mkdir -p auth

  if [ ! -s auth/htpasswd ]; then
    if [ -t 0 ]; then
      echo
      echo "Defina a senha do dashboard Traefik:"
      htpasswd -cB auth/htpasswd admin
    else
      echo "✘ auth/htpasswd ausente e sessão não interativa." >&2
      echo "  Rode: htpasswd -cB $SCRIPT_DIR/auth/htpasswd admin" >&2
      exit 2
    fi
  fi

  docker compose config >/dev/null
  docker compose up -d
  echo "✔ Traefik ativo: https://$DASHBOARD_DOMAIN"
fi

echo
echo "Host pronto."
echo "Novo login pode ser necessário para $ARC_USER receber o grupo docker."
echo "Valide com: bash $SCRIPT_DIR/doctor.sh"
