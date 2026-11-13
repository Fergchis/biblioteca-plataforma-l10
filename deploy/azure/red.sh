#!/usr/bin/env bash
# Red de Azure de la biblioteca (L10, EP3 E2): grupo, VNet, subredes, NSG, IP publica y tabla de rutas.
# Uso, en Git Bash con 'az login' hecho:   bash deploy/azure/red.sh
# Se puede volver a correr: los 'create' de red actualizan lo que ya existe.
# Si cambia tu IP, vuelve a correrlo: actualiza la regla de SSH con la IP nueva.
# La regla ssh-integrante se reescribe entera cada vez: lleva tu IP y las de SSH_EXTRA (ver comun.sh).
set -euo pipefail
cd "$(dirname "$0")"
source comun.sh
MI_IP=$(curl -s https://checkip.amazonaws.com | tr -d "\r\n ")   # la IP de quien corre esto (SSH)
ORIGENES_SSH="$MI_IP/32"; for ip in $SSH_EXTRA; do ORIGENES_SSH="$ORIGENES_SSH ${ip%/32}/32"; done
echo "Grupo $G en $L; SSH permitido desde $ORIGENES_SSH"

# 0. Proveedores: sin registrarlos, una suscripcion nueva no muestra cuotas ni crea recursos
az provider register -n Microsoft.Compute --wait
az provider register -n Microsoft.Network --wait

# 1. Grupo y VNet con dos subredes; ninguna con salida por defecto de Azure
az group create -n $G -l $L -o none
# La VNet y las subredes se crean solo si no existen: volver a crear la VNet con una sola subred
# intenta borrar la privada, y Azure lo rechaza (InUseSubnetCannotBeDeleted) cuando ya tiene a bff.
if ! az network vnet show -g $G -n $VNET -o none 2>/dev/null; then
  az network vnet create -g $G -n $VNET --address-prefixes 10.1.0.0/16 \
    --subnet-name publica --subnet-prefixes 10.1.1.0/24 -o none
fi
# 'vnet subnet create' NO deja defaultOutboundAccess=false si no se pide: se pide explicito
if ! az network vnet subnet show -g $G --vnet-name $VNET -n privada -o none 2>/dev/null; then
  az network vnet subnet create -g $G --vnet-name $VNET -n privada \
    --address-prefixes 10.1.2.0/24 --default-outbound false -o none
fi

# 2. NSG de gw-azure: web desde internet, SSH solo desde tu IP, todo desde la subred privada (NAT)
az network nsg create -g $G -n nsg-gw-azure -o none
az network nsg rule create -g $G --nsg-name nsg-gw-azure -n web --priority 100 \
  --source-address-prefixes Internet --destination-port-ranges 80 443 --protocol Tcp -o none
az network nsg rule create -g $G --nsg-name nsg-gw-azure -n ssh-integrante --priority 110 \
  --source-address-prefixes $ORIGENES_SSH --destination-port-ranges 22 --protocol Tcp -o none
az network nsg rule create -g $G --nsg-name nsg-gw-azure -n desde-privada --priority 120 \
  --source-address-prefixes 10.1.2.0/24 --destination-port-ranges '*' --protocol '*' -o none
# NSG de bff: solo desde la VNet; el resto se niega
az network nsg create -g $G -n nsg-bff -o none
az network nsg rule create -g $G --nsg-name nsg-bff -n desde-vnet --priority 100 \
  --source-address-prefixes 10.1.0.0/16 --destination-port-ranges '*' --protocol '*' -o none
az network nsg rule create -g $G --nsg-name nsg-bff -n deny-resto --priority 4000 --access Deny \
  --source-address-prefixes '*' --destination-port-ranges '*' --protocol '*' -o none

# 3. Tabla de rutas de la privada: 0.0.0.0/0 hacia la IP privada de gw-azure
az network route-table create -g $G -n rt-privada -o none
az network route-table route create -g $G --route-table-name rt-privada -n salida \
  --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address 10.1.1.4 -o none

# 4. Asociar NSG y tabla a las subredes
az network vnet subnet update -g $G --vnet-name $VNET -n publica --nsg nsg-gw-azure -o none
az network vnet subnet update -g $G --vnet-name $VNET -n privada --nsg nsg-bff \
  --route-table rt-privada --default-outbound false -o none

# 5. IP publica estatica de gw-azure, con etiqueta DNS
az network public-ip create -g $G -n pip-gw-azure --sku Standard --allocation-method Static \
  --dns-name "$ETIQUETA" -o none
az network public-ip show -g $G -n pip-gw-azure --query "{ip:ipAddress, fqdn:dnsSettings.fqdn}" -o table
