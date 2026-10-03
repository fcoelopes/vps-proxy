# AWS EC2

## Recomendação inicial

- Ubuntu Server 24.04 LTS.
- instância com pelo menos 2 vCPU / 4 GiB para serviços leves;
- 8 GiB quando ArcLab + ArcPRESS dividirem o host;
- volume gp3;
- Elastic IP quando o hostname precisar permanecer estável.

## Security Group

Entrada mínima:

- TCP 22 a partir dos IPs administrativos;
- TCP 80 de qualquer origem;
- TCP 443 de qualquer origem.

Banco e portas internas não devem entrar no Security Group.

Depois de conectar:

```bash
git clone git@github.com:fcoelopes/vps-proxy.git
cd vps-proxy
sudo ./bootstrap.sh --provider aws --edge
```
