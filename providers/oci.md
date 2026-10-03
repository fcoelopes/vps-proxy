# Oracle Cloud Infrastructure

Use Ubuntu 24.04 quando disponível.

Na VCN/NSG ou Security List, permita:

- SSH da origem administrativa;
- TCP 80;
- TCP 443.

OCI possui firewall de rede e também firewall no sistema operacional. O
bootstrap configura UFW, mas as regras da VCN/NSG continuam sendo
responsabilidade do operador.

Bootstrap:

```bash
git clone git@github.com:fcoelopes/vps-proxy.git
cd vps-proxy
sudo ./bootstrap.sh --provider oci --edge
```
