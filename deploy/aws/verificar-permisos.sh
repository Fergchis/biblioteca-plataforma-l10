#!/usr/bin/env bash
# verificar-permisos.sh · EP3 DSY1107 · VidalStore
#
# Prueba, en la cuenta del Learner Lab que va a alojar AWS, que se pueden hacer las
# cosas que pide el despliegue de la EP3, y deja el resultado en texto. Crea recursos
# de prueba con el prefijo ep3-permisos y los borra al terminar, falle lo que falle.
#
# Uso (Git Bash en Windows, macOS o Linux), desde la raíz de vidalstore-plataforma:
#
#   bash deploy/aws/verificar-permisos.sh                 # escribe deploy/aws/permisos.txt
#   bash deploy/aws/verificar-permisos.sh otra/ruta.txt   # escribe en otra ruta
#
# Requisitos: la sesión del Learner Lab iniciada, AWS CLI v2 con las credenciales de
# «AWS Details» en ~/.aws/credentials (cambian en cada sesión) y el Session Manager
# plugin instalado. Demora entre 3 y 5 minutos.

set -u
export MSYS_NO_PATHCONV=1          # Git Bash: que no convierta /aws/... en una ruta de Windows
export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"
SALIDA="${1:-deploy/aws/permisos.txt}"
PREFIJO="ep3-permisos"
PUERTO_LOCAL=18080

mkdir -p "$(dirname "$SALIDA")"
: > "$SALIDA"

aws_() { aws "$@" 2>&1 | tr -d '\r'; }
linea() { echo "$1" | tee -a "$SALIDA"; }
ok() { linea "OK      $1"; }
falla() { linea "FALLA   $1 :: $(echo "$2" | tr '\n' ' ' | cut -c1-220)"; }
nota() { linea "        $1"; }

VPC=""; IGW=""; SUBRED=""; RT=""; SG=""; EIP_ALLOC=""; INST=""; PF_PID=""

limpiar() {
  linea ""
  linea "Limpieza de los recursos de prueba"
  [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null
  rm -f .ep3-permisos-userdata.sh
  if [ -n "$INST" ]; then
    aws_ ec2 terminate-instances --instance-ids "$INST" > /dev/null
    aws_ ec2 wait instance-terminated --instance-ids "$INST" > /dev/null
    nota "instancia $INST terminada"
  fi
  [ -n "$EIP_ALLOC" ] && aws_ ec2 release-address --allocation-id "$EIP_ALLOC" > /dev/null && nota "Elastic IP liberada"
  [ -n "$SG" ] && aws_ ec2 delete-security-group --group-id "$SG" > /dev/null
  if [ -n "$RT" ]; then
    for A in $(aws_ ec2 describe-route-tables --route-table-ids "$RT" \
        --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws_ ec2 disassociate-route-table --association-id "$A" > /dev/null
    done
    aws_ ec2 delete-route-table --route-table-id "$RT" > /dev/null
  fi
  [ -n "$SUBRED" ] && aws_ ec2 delete-subnet --subnet-id "$SUBRED" > /dev/null
  if [ -n "$IGW" ]; then
    aws_ ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC" > /dev/null
    aws_ ec2 delete-internet-gateway --internet-gateway-id "$IGW" > /dev/null
  fi
  [ -n "$VPC" ] && aws_ ec2 delete-vpc --vpc-id "$VPC" > /dev/null && nota "VPC de prueba borrada"
  linea "Fin: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
trap limpiar EXIT

linea "verificar-permisos.sh · EP3 DSY1107"
linea "Inicio: $(date -u +%Y-%m-%dT%H:%M:%SZ) · región $REGION"

# 0 · Credenciales y plugin
ID=$(aws_ sts get-caller-identity --query Arn --output text)
case "$ID" in
  arn:aws:sts::*) ok "0 credenciales del Learner Lab ($ID)";;
  *) falla "0 credenciales" "$ID"; nota "Copia de nuevo las credenciales de AWS Details: cambian en cada sesión."; exit 1;;
esac
command -v session-manager-plugin > /dev/null && ok "0 Session Manager plugin instalado" \
  || falla "0 Session Manager plugin" "no está en el PATH; la prueba 7 no se puede hacer"

# 1 · VPC con Internet Gateway, subred pública y tabla de rutas
VPC=$(aws_ ec2 create-vpc --cidr-block 10.99.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$PREFIJO}]" --query Vpc.VpcId --output text)
case "$VPC" in vpc-*) ok "1 crear VPC ($VPC)";; *) falla "1 crear VPC" "$VPC"; VPC=""; exit 1;; esac
aws_ ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames '{"Value": true}' > /dev/null
IGW=$(aws_ ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
R=$(aws_ ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC")
[ -z "$R" ] && ok "1 Internet Gateway asociado ($IGW)" || { falla "1 Internet Gateway" "$IGW $R"; exit 1; }
SUBRED=$(aws_ ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.99.1.0/24 \
  --availability-zone "${REGION}a" --query Subnet.SubnetId --output text)
RT=$(aws_ ec2 create-route-table --vpc-id "$VPC" --query RouteTable.RouteTableId --output text)
aws_ ec2 create-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" > /dev/null
R=$(aws_ ec2 associate-route-table --route-table-id "$RT" --subnet-id "$SUBRED" --query AssociationId --output text)
case "$R" in rtbassoc-*) ok "1 subred pública con ruta 0.0.0.0/0 al Internet Gateway";; *) falla "1 subred y rutas" "$R"; exit 1;; esac

# 2 · Security Group como el de gw-aws: 80 desde internet y 443 desde una sola IP
MI_IP=$(curl -s --max-time 8 https://checkip.amazonaws.com | tr -d '\r\n ')
SG=$(aws_ ec2 create-security-group --group-name "$PREFIJO-gw" --description "ep3 prueba gw" \
  --vpc-id "$VPC" --query GroupId --output text)
R1=$(aws_ ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 --query Return --output text)
R2=$(aws_ ec2 authorize-security-group-ingress --group-id "$SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,IpRanges=[{CidrIp=${MI_IP}/32}]" --query Return --output text)
[ "$R1" = "True" ] && [ "$R2" = "True" ] && ok "2 Security Group con el 80 abierto y un puerto solo para la IP $MI_IP/32" \
  || falla "2 reglas del Security Group" "$R1 $R2"

# 3 · EC2 con LabInstanceProfile, sin puerto 22 ni par de llaves, con IP privada fija
AMI=$(aws_ ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)
cat > .ep3-permisos-userdata.sh <<'EOF'
#!/bin/bash
cat > /opt/eco.py <<'PY'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        cuerpo = json.dumps({"servicio": "ep3-permisos", "ruta": self.path}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(cuerpo)
http.server.HTTPServer(("0.0.0.0", 8080), H).serve_forever()
PY
nohup python3 /opt/eco.py > /var/log/eco.log 2>&1 &
EOF
INST=$(aws_ ec2 run-instances --image-id "$AMI" --instance-type t3.nano --subnet-id "$SUBRED" \
  --security-group-ids "$SG" --iam-instance-profile Name=LabInstanceProfile \
  --private-ip-address 10.99.1.10 --user-data file://.ep3-permisos-userdata.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PREFIJO}]" \
  --query 'Instances[0].InstanceId' --output text)
rm -f .ep3-permisos-userdata.sh
case "$INST" in
  i-*) ok "3 EC2 t3.nano con LabInstanceProfile e IP privada fija 10.99.1.10 ($INST)";;
  *) falla "3 lanzar EC2 con LabInstanceProfile" "$INST"; INST=""; exit 1;;
esac
aws_ ec2 wait instance-running --instance-ids "$INST" > /dev/null

# 4 · Elastic IP
EIP_ALLOC=$(aws_ ec2 allocate-address --domain vpc --query AllocationId --output text)
case "$EIP_ALLOC" in
  eipalloc-*)
    R=$(aws_ ec2 associate-address --allocation-id "$EIP_ALLOC" --instance-id "$INST" --query AssociationId --output text)
    case "$R" in eipassoc-*) ok "4 Elastic IP asignada y asociada";; *) falla "4 asociar Elastic IP" "$R";; esac;;
  *) falla "4 asignar Elastic IP" "$EIP_ALLOC"; EIP_ALLOC="";;
esac
sleep 5
IPPUB=$(aws_ ec2 describe-instances --instance-ids "$INST" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
nota "IP pública de la instancia: $IPPUB"

# 5 · Desactivar source/dest check (lo necesita la NAT instance)
R=$(aws_ ec2 modify-instance-attribute --instance-id "$INST" --no-source-dest-check)
[ -z "$R" ] && ok "5 desactivar source/dest check (NAT instance)" || falla "5 source/dest check" "$R"

# 6 · Session Manager: la instancia se registra y acepta comandos
ESTADO=""
for i in $(seq 1 40); do
  ESTADO=$(aws_ ssm describe-instance-information --filters "Key=InstanceIds,Values=$INST" \
    --query 'InstanceInformationList[0].PingStatus' --output text)
  [ "$ESTADO" = "Online" ] && break
  sleep 10
done
if [ "$ESTADO" = "Online" ]; then
  ok "6 la instancia aparece en Session Manager (Online)"
  CMD=$(aws_ ssm send-command --instance-ids "$INST" --document-name AWS-RunShellScript \
    --parameters 'commands=["hostname -I"]' --query Command.CommandId --output text)
  sleep 6
  R=$(aws_ ssm get-command-invocation --command-id "$CMD" --instance-id "$INST" \
    --query StandardOutputContent --output text)
  case "$R" in *10.99.1.10*) ok "6 comando ejecutado por Session Manager (responde $R)";; *) falla "6 ejecutar comando" "$R";; esac
else
  falla "6 Session Manager" "la instancia no quedó Online en 400 s (estado: $ESTADO)"
fi

# 7 · Port forwarding de Session Manager hasta el 8080 de la instancia
if [ "$ESTADO" = "Online" ] && command -v session-manager-plugin > /dev/null; then
  aws ssm start-session --target "$INST" --document-name AWS-StartPortForwardingSession \
    --parameters "portNumber=8080,localPortNumber=$PUERTO_LOCAL" > /dev/null 2>&1 &
  PF_PID=$!
  disown "$PF_PID" 2>/dev/null
  R=""
  for i in $(seq 1 15); do
    sleep 2
    R=$(curl -s --max-time 3 "http://localhost:$PUERTO_LOCAL/salud" || true)
    case "$R" in *ep3-permisos*) break;; esac
  done
  case "$R" in
    *ep3-permisos*) ok "7 port forwarding: localhost:$PUERTO_LOCAL llega al 8080 de la instancia";;
    *) falla "7 port forwarding" "sin respuesta en localhost:$PUERTO_LOCAL";;
  esac
  kill "$PF_PID" 2>/dev/null; PF_PID=""
fi

# 8 · El nombre <ip-con-guiones>.sslip.io resuelve a la IP pública (el HTTPS de gw-aws lo usa)
if [ -n "$IPPUB" ] && [ "$IPPUB" != "None" ]; then
  NOMBRE="$(echo "$IPPUB" | tr '.' '-').sslip.io"
  R=$(nslookup "$NOMBRE" 2>&1 | tr -d '\r')
  case "$R" in *"$IPPUB"*) ok "8 $NOMBRE resuelve a $IPPUB";; *) falla "8 DNS de sslip.io" "$R";; esac
fi

# 9 · Un puerto sin regla no responde desde internet
if [ -n "$IPPUB" ] && [ "$IPPUB" != "None" ]; then
  R=$(curl -s --max-time 8 "http://$IPPUB:8080/" || echo "sin-respuesta")
  case "$R" in
    *ep3-permisos*) nota "9 desde esta IP el 8080 responde, porque la regla 2 lo permite: correcto";;
    *) falla "9 regla por IP" "la IP permitida no llega al 8080: $R";;
  esac
  R=$(curl -s --max-time 8 "http://$IPPUB:22/" || echo "sin-respuesta")
  [ "$R" = "sin-respuesta" ] && ok "9 el puerto 22 no responde: no hay regla que lo abra" \
    || falla "9 puerto 22" "respondió: $R"
fi

linea ""
linea "Resumen: $(grep -c '^OK' "$SALIDA") OK y $(grep -c '^FALLA' "$SALIDA") FALLA"
