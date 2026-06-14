# infra-proxy

Reverse proxy centralizado com Traefik. Fica rodando na VPS e roteia o tráfego para cada ferramenta pelo subdomínio.

---

## O que é isso e por que existe

Você tem uma VPS com um único IP. Quer colocar vários projetos nela e acessar cada um por um subdomínio diferente:

```
projeto#1.fcoelds.dev.br     →  EPI Control
projeto#2.fcoelds.dev.br     →  ArcFlash NR-10
projeto#3.fcoleds.tec.br     →  rbd-graph
```

O Traefik fica na porta 80/443, intercepta todas as requisições e encaminha para o container certo baseado no domínio. Você sobe um projeto novo e o Traefik detecta automaticamente — sem editar nenhum arquivo de configuração central.

---

## Estrutura na VPS

```
/srv/
├── proxy/                    ← este repositório
│   ├── docker-compose.yml
│   ├── traefik.yml
│   ├── acme.json             ← gerado automaticamente (NÃO commitar)
│   └── .env                  ← token Cloudflare (NÃO commitar)
│
├── epi-control/              ← cada projeto no seu diretório
├── arcflash/
├── rbd-graph/
└── exemplo-app/
```

Cada projeto é um repositório Git independente clonado em `/srv/nome-do-projeto`.

---

## Setup inicial (fazer uma única vez)

### 1. Clonar o repositório na VPS

```bash
git clone git@github.com:fcoelopes/infra-proxy.git /srv/proxy
cd /srv/proxy
```

### 2. Criar a rede compartilhada do Docker

```bash
docker network create proxy
```

Todos os projetos vão usar esta mesma rede para se comunicar com o Traefik.

### 3. Criar o acme.json

Este arquivo armazena os certificados SSL. Precisa existir antes de subir o Traefik e ter permissão 600 obrigatoriamente — caso contrário o Traefik recusa iniciar.

```bash
touch /srv/proxy/acme.json
chmod 600 /srv/proxy/acme.json
```

### 4. Criar o .env com o token do Cloudflare

```bash
cp .env.example .env
nano .env
```

Preencher `CF_DNS_API_TOKEN` com o token gerado em:
https://dash.cloudflare.com/profile/api-tokens

Permissões necessárias no token:
- Zone > DNS > Edit
- Zone > Zone > Read
- Escopo: apenas a zona do seu domínio

### 5. Gerar senha para o dashboard

O dashboard do Traefik fica em `traefik.fcoleds.dev.br` e é protegido por usuário e senha. Para gerar o hash:

```bash
# Instalar htpasswd se não tiver
apt install apache2-utils -y

# Gerar hash (vai pedir a senha duas vezes)
sudo htpasswd -cB /srv/proxy/auth/htpasswd admin
```

### 6. Trocar os placeholders no traefik.yml

```yaml
email: seuemail@exemplo.com   # trocar pelo seu email real
```

### 7. Trocar os placeholders no docker-compose.yml

Substituir todas as ocorrências de `fcoelds.dev.br` pelo domínio real.

### 8. Subir o Traefik

```bash
cd /srv/proxy
docker compose up -d
```

Verificar se subiu:

```bash
docker compose logs -f
```

### 9. Configurar DNS no Cloudflare

Criar dois registros A apontando para o IP da VPS:

| Tipo | Nome                | Conteúdo    | Proxy   |
|------|---------------------|-------------|---------|
| A    | intops.tec.br       | IP_DA_VPS   |  ☁️ On  |
| A    | *.intops.tec.br     | IP_DA_VPS   |  ☁️ On  |

O registro wildcard (`*`) faz com que qualquer subdomínio resolva automaticamente para a VPS.

---

## Como adicionar um novo projeto

### Passo 1 — O projeto precisa ter estes arquivos

```
meu-projeto/
├── Dockerfile
├── docker-compose.yml     ← com as labels do Traefik
├── .env.example
├── .env                   ← só na VPS, nunca no Git
└── .gitignore
```

### Passo 2 — No docker-compose.yml do projeto, adicionar as labels

```yaml
services:
  meu-projeto:
    build: .
    container_name: meu-projeto
    restart: unless-stopped
    expose:
      - "8000"              # porta que a app escuta internamente
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      # Trocar meu-projeto pelo nome do router (único entre todos os projetos)
      # Trocar o subdomínio pelo desejado
      - "traefik.http.routers.meu-projeto.rule=Host(`meu-projeto.intops.tec.br`)"
      - "traefik.http.routers.meu-projeto.entrypoints=websecure"
      - "traefik.http.routers.meu-projeto.tls.certresolver=cloudflare"
      - "traefik.http.services.meu-projeto.loadbalancer.server.port=8000"

networks:
  proxy:
    external: true          # mesma rede do Traefik
```

**As 3 coisas que mudam para cada projeto:**
1. Nome do router (`meu-projeto`) — deve ser único, use o nome do projeto
2. Subdomínio (`meu-projeto.fcoelds.dev.br`)
3. Porta interna (`8000`) — a porta que a app escuta dentro do container

### Passo 3 — Clonar e subir na VPS

```bash
# Clonar o projeto
git clone git@github.com:fcoelopes/meu-projeto.git /srv/meu-projeto
cd /srv/meu-projeto

# Criar o .env a partir do exemplo
cp .env.example .env
nano .env   # preencher as variáveis

# Subir
docker compose up -d --build
```

Pronto. O Traefik detecta o container em segundos e o subdomínio já está funcionando com HTTPS.

---

## Deploy automático via GitHub Actions

Cada projeto pode ter um workflow que faz o deploy automaticamente a cada push na branch `main`. Ver o arquivo `exemplo-app/.github/workflows/deploy.yml`.

### Secrets necessários no GitHub

Configurar em: Settings > Secrets and variables > Actions

| Secret        | Valor                          |
|---------------|--------------------------------|
| `VPS_HOST`    | IP da VPS (ex: 94.130.149.144) |
| `VPS_USER`    | Usuário SSH (ex: root)         |
| `VPS_SSH_KEY` | Chave SSH privada              |

### Como gerar a chave SSH para o GitHub Actions

```bash
# Na sua máquina local
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions

# Copiar a chave pública para a VPS
ssh-copy-id -i ~/.ssh/github_actions.pub root@IP_DA_VPS

# O conteúdo da chave privada vai no secret VPS_SSH_KEY
cat ~/.ssh/github_actions
```

---

## Comandos úteis do dia a dia

```bash
# Ver todos os containers rodando
docker ps

# Ver logs do Traefik em tempo real
cd /srv/proxy && docker compose logs -f

# Ver logs de um projeto específico
cd /srv/epi-control && docker compose logs -f

# Reiniciar um projeto sem downtime
cd /srv/epi-control && docker compose up -d --build

# Derrubar um projeto (Traefik para de rotear automaticamente)
cd /srv/epi-control && docker compose down

# Limpar imagens antigas
docker image prune -f
```

---

## O que não commitar nunca

```
.env          → tem senhas e tokens
acme.json     → tem chaves privadas dos certificados SSL
```

Ambos estão no `.gitignore`. Na VPS eles ficam apenas em disco, criados manualmente uma única vez.
