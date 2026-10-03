# Hetzner Cloud

## Recomendação

- Ubuntu 24.04;
- volume persistente somente quando houver necessidade separada do disco raiz;
- Firewall Hetzner associado ao servidor.

Regras de entrada:

- SSH apenas de origens administrativas;
- TCP 80;
- TCP 443.

Bootstrap:

```bash
git clone git@github.com:fcoelopes/vps-proxy.git
cd vps-proxy
sudo bash ./bootstrap.sh --provider hetzner --edge
```
