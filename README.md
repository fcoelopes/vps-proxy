# vps-proxy

Bootstrap e contrato operacional para hosts que executam aplicações do
ecossistema Arc.

A ideia é simples: a origem da VM pode ser **AWS, Contabo, Hetzner, OCI ou
outro provedor**, mas depois do bootstrap o host deve parecer igual para
ArcLab, ArcPRESS, Clarc e os próximos projetos.

O Traefik continua neste repositório, mas agora é **um componente da plataforma
do host**, não a finalidade inteira do projeto.

## O que o repositório prepara

```text
VM Ubuntu/Debian limpa
        │
        ▼
bootstrap.sh
        │
        ├── usuário de operação não-root
        ├── Docker Engine + Compose
        ├── rotação de logs Docker
        ├── unattended security upgrades
        ├── swap
        ├── UFW: SSH + 80 + 443
        ├── /srv/arc/{apps,data,backups}
        ├── rede Docker externa "proxy"
        └── opcional: Traefik + Let's Encrypt
                        │
                        ▼
                  ARC-READY HOST
                        │
           ┌────────────┼────────────┐
           ▼            ▼            ▼
        ArcLab       ArcPRESS       Clarc
```

O estado final está definido em [docs/HOST_CONTRACT.md](docs/HOST_CONTRACT.md).

## Providers

Os provedores mudam a forma de **criar** a VM e abrir o firewall externo. O
bootstrap do sistema operacional é o mesmo.

Guias:

- [AWS EC2](providers/aws.md)
- [Contabo](providers/contabo.md)
- [Hetzner Cloud](providers/hetzner.md)
- [OCI](providers/oci.md)

O repositório não tenta esconder diferenças de cloud: Security Group, NSG/VCN,
firewall Hetzner, IP elástico e afins continuam sendo responsabilidade da
camada do provedor. O objetivo aqui é normalizar o host depois que o SSH existe.

## Bootstrap

Exemplo em uma Contabo limpa:

```bash
git clone git@github.com:fcoelopes/vps-proxy.git
cd vps-proxy

sudo bash ./bootstrap.sh \
  --provider contabo \
  --user arc \
  --edge \
  --dashboard-domain traefik.seudominio.com \
  --acme-email ops@seudominio.com
```

O mesmo comando muda apenas em `--provider` para AWS, Hetzner ou OCI.

Sem borda pública:

```bash
sudo bash ./bootstrap.sh --provider aws --user arc
```

Depois:

```bash
bash ./doctor.sh
```

Saída esperada:

```text
ARC-READY
```

## Contrato de rede para aplicações

Cada aplicação mantém sua própria rede privada. Somente o gateway HTTP entra na
rede Docker externa `proxy`.

```text
Internet
   │
   ▼
Traefik :80/:443
   │
   └── rede "proxy"
       ├── arclab-nginx
       ├── arcpress-proxy
       └── clarc-gateway
```

Postgres, MinIO, workers, ClamAV, pgBouncer e equivalentes **não** entram nessa
rede compartilhada.

Exemplo de integração:

```yaml
services:
  gateway:
    networks:
      - default
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.app.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=80"

networks:
  proxy:
    external: true
```

## Edge Traefik

Quando `--edge` é usado, o bootstrap:

1. grava `.env` com domínio do dashboard e e-mail ACME;
2. cria `acme.json` com permissão 600;
3. cria autenticação Basic Auth do dashboard;
4. sobe Traefik e o Docker Socket Proxy.

O Traefik é o único dono das portas 80/443.

A descoberta Docker não recebe o socket diretamente. Ela passa por
`docker-socket-proxy`, numa rede interna separada, com acesso de leitura
limitado aos endpoints necessários.

TLS é emitido e renovado pelo Traefik via Let's Encrypt HTTP-01.

## Diretórios do host

O bootstrap cria:

```text
/srv/arc/
├── apps/
├── data/
└── backups/
```

O objetivo é dar um lugar previsível para novos serviços e dados operacionais,
sem obrigar cada aplicação a inventar um layout de máquina diferente.

## Segurança

O bootstrap é propositalmente conservador:

- não desativa o acesso SSH existente;
- não desativa root automaticamente;
- não mexe em Security Groups/NSG/firewalls externos;
- não sobrescreve um `/etc/docker/daemon.json` já existente;
- não publica banco ou storage;
- habilita UFW apenas com SSH, 80 e 443 por padrão.

Hardening mais agressivo deve ser uma evolução explícita, não uma surpresa
durante o primeiro bootstrap.

## Arquivos sensíveis

Nunca commitar:

```text
.env
acme.json
auth/htpasswd
```

## Próxima evolução natural

A camada de **provisionamento** pode ser adicionada depois, sem misturar com o
contrato do host:

```text
providers/
  aws/       Terraform/cloud-init
  hetzner/   Terraform/cloud-init
  oci/       Terraform/cloud-init
  contabo/   API/cloud-init quando aplicável
```

O ponto importante é que todos terminem executando o mesmo `bootstrap.sh` e
entregando o mesmo **Arc-ready host**.
