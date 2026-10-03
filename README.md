# vps-proxy

Borda HTTP/HTTPS central da VPS Contabo. O Traefik é o único serviço que publica
as portas 80 e 443; ArcLab, ArcPRESS, Clarc e outros stacks entram na rede Docker
externa `proxy` e são descobertos por labels.

## Arquitetura

```text
Internet
  |
  | 80/443
  v
Traefik
  |
  +-- proxy (rede Docker externa)
      +-- arclab-nginx
      +-- arcpress-proxy
      +-- clarc (futuro)
```

O Traefik não monta o Docker socket diretamente. A descoberta passa por
`tecnativa/docker-socket-proxy`, numa rede interna separada, liberando apenas
os endpoints de leitura necessários para containers, eventos e redes.

TLS é emitido e renovado pelo próprio Traefik via Let's Encrypt HTTP-01. Não há
Cloudflare Tunnel e não há Certbot nos projetos. Cloudflare pode continuar sendo
usado apenas como DNS/proxy externo, se desejado.

## Primeiro bootstrap da VPS

```bash
sudo mkdir -p /srv
sudo chown "$USER":"$USER" /srv

git clone git@github.com:fcoelopes/vps-proxy.git /srv/proxy
cd /srv/proxy

docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

cp .env.example .env
nano .env

touch acme.json
chmod 600 acme.json

mkdir -p auth
sudo apt-get update
sudo apt-get install -y apache2-utils
htpasswd -cB auth/htpasswd admin

docker compose config
docker compose up -d
docker compose ps
```

As portas TCP 80 e 443 precisam estar acessíveis da Internet para o HTTP-01.
No firewall da VPS, deixe públicas apenas SSH, 80 e 443.

## DNS

Crie registros A para cada hostname apontando para o IP público da Contabo:

```text
traefik.fcoelds.dev.br  -> IP_DA_VPS
<dominio-do-arclab>     -> IP_DA_VPS
arcpress.arc.tec.br     -> IP_DA_VPS
```

Não é necessário criar túnel. Se usar o proxy da Cloudflare, mantenha o origin
alcançável em 80/443; para o primeiro bootstrap do certificado, DNS-only é a
opção mais simples.

## Contrato para aplicações

Cada aplicação mantém sua rede privada. Somente seu gateway HTTP entra também
na rede externa `proxy`.

Exemplo:

```yaml
services:
  gateway:
    networks:
      - default
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.app.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=80"

networks:
  proxy:
    external: true
```

Banco, storage, workers e demais serviços não devem ser conectados à `proxy`.

## Operação

```bash
cd /srv/proxy
docker compose pull
docker compose up -d
docker compose ps
docker compose logs -f traefik
```

O arquivo `acme.json` contém material privado dos certificados e nunca deve ser
commitado. O mesmo vale para `.env` e `auth/htpasswd`.
