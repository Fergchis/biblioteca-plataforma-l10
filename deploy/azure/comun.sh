# Variables comunes de los scripts de Azure de la biblioteca. Se cargan con 'source comun.sh'.
G=${G:-biblioteca-l10}                       # grupo de recursos: todo queda dentro de el
L=${L:-northcentralus}                       # region que acepta la politica "Ubicaciones permitidas"
ETIQUETA=${ETIQUETA:-biblioteca-l10}          # etiqueta DNS de gw-azure: <etiqueta>.<region>.cloudapp.azure.com
CLAVE=${CLAVE:-$HOME/.ssh/biblioteca-azure}  # llave SSH de quien aloja Azure (se genera si no existe)
VNET=vnet-biblioteca
# IP extra que pueden entrar por SSH a gw-azure, separadas por espacio (la de quien corre red.sh entra siempre):
#   SSH_EXTRA="190.20.30.40 181.50.60.70" bash deploy/azure/red.sh
SSH_EXTRA=${SSH_EXTRA:-}

# az.exe en Git Bash deja \r al final de cada linea de -o tsv: se quita (como aws_ en deploy/aws/comun.sh)
az_() { az "$@" | tr -d '\r'; }
# Ruta local para un programa de Windows (az.exe): C:/Users/... en Git Bash; igual en macOS y Linux
ruta_local() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }
