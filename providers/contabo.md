# Contabo

Contabo normalmente entrega a VM já com IP público. Use Ubuntu 24.04 e faça o
controle de entrada pelo firewall disponível no painel, quando houver, e pelo
UFW configurado no host.

Entrada mínima:

- SSH;
- TCP 80;
- TCP 443.

Bootstrap:

```bash
git clone git@github.com:fcoelopes/vps-proxy.git
cd vps-proxy
sudo bash ./bootstrap.sh --provider contabo --edge
```
