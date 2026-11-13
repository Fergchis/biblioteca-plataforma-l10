#!/usr/bin/env bash
# Maquinas de Azure de la biblioteca (L10, EP3 E2): gw-azure (NAT y gateway) y bff (sin IP publica).
# Requiere red.sh ya corrido. Uso, en Git Bash:   bash deploy/azure/maquinas.sh
# Opcional: CORREO=<correo> para recibir el aviso del apagado automatico.
# Se puede volver a correr: si una VM ya existe, no la crea de nuevo.
set -euo pipefail
cd "$(dirname "$0")"
source comun.sh
mkdir -p "$(dirname "$CLAVE")"
[ -f "$CLAVE" ] || ssh-keygen -q -t ed25519 -N "" -f "$CLAVE"
PUB=$(ruta_local "$CLAVE.pub")   # az.exe no entiende /c/Users/...
existe() { az vm show -g $G -n "$1" --query id -o tsv >/dev/null 2>&1; }

# 1. gw-azure: IP privada fija, IP publica, IP forwarding en la NIC; cloud-init instala Docker y el NAT
if ! existe gw-azure; then
  az network nic create -g $G -n nic-gw-azure --vnet-name $VNET --subnet publica \
    --private-ip-address 10.1.1.4 --public-ip-address pip-gw-azure --ip-forwarding true -o none
  az vm create -g $G -n gw-azure --image Ubuntu2404 --size Standard_B2ats_v2 --nics nic-gw-azure \
    --admin-username azureuser --ssh-key-values "$PUB" --custom-data cloud-init-gw-azure.yaml \
    --os-disk-size-gb 30 --storage-sku StandardSSD_LRS -o none
fi
IP=$(az_ network public-ip show -g $G -n pip-gw-azure --query ipAddress -o tsv)

# 2. Esperar a que cloud-init termine en gw-azure: sin NAT listo, bff no puede bajar Docker
SSHO="-i $CLAVE -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
until ssh $SSHO azureuser@$IP true 2>/dev/null; do echo "esperando SSH de gw-azure..."; sleep 10; done
ssh $SSHO azureuser@$IP "cloud-init status --wait"

# 3. bff: sin IP publica, IP privada fija; cloud-init instala Docker (baja por el NAT)
if ! existe bff; then
  az network nic create -g $G -n nic-bff --vnet-name $VNET --subnet privada \
    --private-ip-address 10.1.2.4 -o none
  az vm create -g $G -n bff --image Ubuntu2404 --size Standard_B2als_v2 --nics nic-bff \
    --admin-username azureuser --ssh-key-values "$PUB" --custom-data cloud-init-bff.yaml \
    --os-disk-size-gb 30 --storage-sku StandardSSD_LRS -o none
fi

# 4. Apagado automatico (desasigna) a las 03:00 UTC, las 00:00 en Chile en horario de verano
for v in gw-azure bff; do
  az vm auto-shutdown -g $G -n $v --time 0300 ${CORREO:+--email "$CORREO"} -o none
done

# 5. Config de SSH para entrar a bff saltando por gw-azure
# StrictHostKeyChecking accept-new: acepta la huella la primera vez (bff no se puede verificar a mano)
cat > "$HOME/.ssh/biblioteca-azure.config" <<EOC
Host gw-azure bff
  StrictHostKeyChecking accept-new
Host gw-azure
  HostName $IP
  User azureuser
  IdentityFile $CLAVE
Host bff
  HostName 10.1.2.4
  User azureuser
  IdentityFile $CLAVE
  ProxyJump gw-azure
EOC
echo "gw-azure: $(az_ network public-ip show -g $G -n pip-gw-azure --query dnsSettings.fqdn -o tsv) ($IP)"
echo "SSH: ssh -F ~/.ssh/biblioteca-azure.config gw-azure   y   ssh -F ~/.ssh/biblioteca-azure.config bff"
echo "Esa IP publica es la que va en la regla 443 de sg-gw en AWS."
