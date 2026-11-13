#!/usr/bin/env bash
# Enciende las dos VM: primero gw-azure (el NAT de bff), despues bff.
set -euo pipefail
cd "$(dirname "$0")"; source comun.sh
az vm start -g $G -n gw-azure
az vm start -g $G -n bff
az vm list -g $G -d --query "[].{vm:name, estado:powerState, ip:publicIps}" -o table
