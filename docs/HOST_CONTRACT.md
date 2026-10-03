# Contrato de host Arc

Um **host Arc-ready** é uma VM Linux preparada para receber produtos Arc sem que
cada aplicação precise saber se está rodando em AWS, Contabo, Hetzner ou OCI.

## Estado esperado

Após o bootstrap:

- Ubuntu 24.04 LTS é a referência; Ubuntu 22.04 e Debian 12 são aceitos.
- existe um usuário não-root de operação/deploy;
- Docker Engine + Compose plugin estão disponíveis;
- o usuário de operação pertence ao grupo `docker`;
- atualização automática de segurança está habilitada;
- swap existe quando solicitado;
- UFW, quando habilitado, permite somente SSH, HTTP e HTTPS;
- existem `/srv/arc/apps`, `/srv/arc/data` e `/srv/arc/backups`;
- existe a rede Docker externa `proxy`;
- o Traefik pode ser instalado como componente de edge, mas não é requisito
  para workloads privados;
- nenhum banco ou serviço de aplicação é instalado pelo bootstrap.

## Separação de responsabilidades

### Provider

AWS, OCI, Hetzner e Contabo são responsáveis por:

- criar a VM;
- associar disco e IP;
- configurar firewall/security group externo;
- disponibilizar acesso SSH inicial.

### vps-proxy

Este repositório normaliza o sistema operacional e cria o contrato Arc-ready.

### Aplicações

ArcLab, ArcPRESS, Clarc e outros projetos são responsáveis pelos próprios
containers, bancos, volumes, secrets, migrations, backups de aplicação e
health checks.

## Rede

A única rede compartilhada entre stacks é:

```text
proxy
```

Somente gateways HTTP podem entrar nela. Postgres, MinIO, workers, ClamAV,
pgBouncer e equivalentes permanecem em redes privadas de cada stack.

## Portas públicas

O contrato padrão do host é:

```text
22/tcp    SSH (ou a porta escolhida pelo operador)
80/tcp    HTTP / ACME
443/tcp   HTTPS
```

Aplicações não publicam novas portas no host sem decisão explícita.

## Idempotência

Rodar o bootstrap novamente não deve destruir configuração de aplicação nem
recriar dados. Ele pode atualizar pacotes do host, validar pré-requisitos e
garantir que diretórios/rede base existam.
