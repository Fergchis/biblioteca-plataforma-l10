#!/usr/bin/env bash
# Desasigna las dos VM (dejan de cobrar computo; la IP publica estatica y los discos se conservan).
set -euo pipefail
cd "$(dirname "$0")"; source comun.sh
az vm deallocate -g $G -n bff
az vm deallocate -g $G -n gw-azure
az vm list -g $G -d --query "[].{vm:name, estado:powerState}" -o table
