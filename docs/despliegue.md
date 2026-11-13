# Despliegue en AWS y Azure · biblioteca · E2

La red de `docs/red.md` y la capa de datos se desplegaron en Learner Lab (`us-east-1`) el 12 de noviembre de 2026; la red y máquinas Azure se prepararon el 13 de noviembre de 2026 con los scripts de `deploy/azure/`.

## Cómo se levantó

```bash
bash deploy/aws/01-red.sh
bash deploy/aws/02-maquinas.sh
bash deploy/aws/03-subir.sh
bash deploy/aws/04-levantar.sh
bash deploy/aws/05-tunel.sh
bash deploy/aws/06-evidencia.sh
ETIQUETA=biblioteca-fergchis-l10 bash deploy/azure/red.sh
ETIQUETA=biblioteca-fergchis-l10 bash deploy/azure/maquinas.sh
bash deploy/azure/apagar.sh
```

## 1 · Las máquinas y sus IP

```text
$ aws ec2 describe-instances --output table --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,PublicIpAddress]"
--------------------------------------------
|             DescribeInstances            |
+---------+--------------+-----------------+
|  mq-2   |  10.0.22.12  |  None           |
|  mq-1   |  10.0.21.11  |  None           |
|  datos  |  10.0.21.30  |  None           |
|  nat    |  10.0.1.10   |  3.215.179.101  |
|  gestion|  10.0.11.20  |  None           |
|  mq-3   |  10.0.21.13  |  None           |
+---------+--------------+-----------------+
```

Solo NAT tiene IP pública; las demás máquinas están en subredes privadas.

## 2 · Nadie abre el 22

```text
$ aws ec2 describe-security-groups --filters Name=ip-permission.from-port,Values=22 --query "SecurityGroups[].GroupName"
[]
```

La consulta no encontró grupos que abran el puerto 22; se utiliza Session Manager.

## 3 · El quórum de KRaft: tres votantes

```text
$ $K/kafka-metadata-quorum.sh --bootstrap-server 10.0.21.11:9092 describe --status
ClusterId:              QmlibGlvdGVjYS1LYWZrYQ
LeaderId:               1
LeaderEpoch:            1
HighWatermark:          713
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [{"id": 1, "endpoints": ["CONTROLLER://10.0.21.11:9093"]}, {"id": 2, "endpoints": ["CONTROLLER://10.0.22.12:9093"]}, {"id": 3, "endpoints": ["CONTROLLER://10.0.21.13:9093"]}]
CurrentObservers:       [{"id": 4, "directoryId": "dTbqGRmcKPhnri1zft_H8w"}, {"id": 6, "directoryId": "4-pDVVdioNddgazex9STBg"}, {"id": 5, "directoryId": "syBOC1JlnVlZQNzOekF4Tw"}]
```

Los votantes 1, 2 y 3 corresponden a los controllers de las tres máquinas MQ.

## 4 · `biblioteca.prestamos`: tres particiones con ISR de tres

```text
$ $K/kafka-topics.sh --bootstrap-server 10.0.21.11:9092 --describe --topic biblioteca.prestamos
Topic: biblioteca.prestamos	TopicId: bxfAOZ6tTlqHU0GejVMC1g	PartitionCount: 3	ReplicationFactor: 3	Configs: min.insync.replicas=2,cleanup.policy=delete,retention.ms=604800000
	Topic: biblioteca.prestamos	Partition: 0	Leader: 6	Replicas: 6,4,5	Isr: 6,4,5	Elr: 	LastKnownElr: 
	Topic: biblioteca.prestamos	Partition: 1	Leader: 4	Replicas: 4,5,6	Isr: 4,5,6	Elr: 	LastKnownElr: 
	Topic: biblioteca.prestamos	Partition: 2	Leader: 5	Replicas: 5,6,4	Isr: 5,6,4	Elr: 	LastKnownElr:
```

Las tres particiones tienen tres réplicas al día en el ISR.

## 5 · Los mensajes de la noche, por partición

```text
$ $K/kafka-get-offsets.sh --bootstrap-server 10.0.21.11:9092 --topic biblioteca.lecturas
biblioteca.lecturas:0:492
biblioteca.lecturas:1:2279
biblioteca.lecturas:2:213
$ $K/kafka-get-offsets.sh --bootstrap-server 10.0.21.11:9092 --topic biblioteca.prestamos
biblioteca.prestamos:0:136
biblioteca.prestamos:1:145
biblioteca.prestamos:2:123
```

Los offsets finales suman 2984 lecturas y 404 préstamos.

## RabbitMQ · dos nodos en clúster

```text
$ docker exec biblioteca-rabbit-rabbit-1 rabbitmqctl cluster_status 2>&1 | sed -n "/^Disk Nodes/,/^Listeners/p" | sed "\$d"
Disk Nodes
rabbit@mq-1
rabbit@mq-2
Running Nodes
rabbit@mq-1
rabbit@mq-2
Versions
rabbit@mq-1: RabbitMQ 4.3.7 on Erlang 27.3.4.19
rabbit@mq-2: RabbitMQ 4.3.7 on Erlang 27.3.4.19
CPU Cores
Node: rabbit@mq-1, available CPU cores: 2
Node: rabbit@mq-2, available CPU cores: 2
Maintenance status
Node: rabbit@mq-1, status: not under maintenance
Node: rabbit@mq-2, status: not under maintenance
Alarms
(none)
Network Partitions
(none)
```

Ambos nodos están activos sin alarmas ni particiones de red informadas.

## Postgres · arriba en `datos`

```text
$ docker ps --filter name=biblioteca-datos --format "{{.Names}}  {{.Image}}  {{.Status}}"
biblioteca-datos-postgres-1  postgres:18  Up 4 minutes (healthy)
$ docker exec biblioteca-datos-postgres-1 sh -c "psql -U \$POSTGRES_USER -d \$POSTGRES_DB -tAc \"select version()\""
PostgreSQL 18.7 (Debian 18.7-1.pgdg13+2) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
```

PostgreSQL 18 está activo y sano.

## 6 · Azure: bff sale por gw-azure

```text
$ ssh -F ~/.ssh/biblioteca-azure.config gw-azure 'hostname; ip -4 addr show eth0|grep inet; docker --version; cat /proc/sys/net/ipv4/ip_forward; sudo iptables -t nat -S POSTROUTING|grep MASQ'
gw-azure
    inet 10.1.1.4/24 metric 100 brd 10.1.1.255 scope global eth0
Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2
1
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
-A POSTROUTING -s 10.1.2.0/24 -o eth0 -j MASQUERADE
$ ssh -F ~/.ssh/biblioteca-azure.config bff 'hostname; ip -4 addr show eth0|grep inet; cloud-init status --wait; docker --version; echo -n "salida: "; curl -s ifconfig.me; echo; ip route|head -2'
Warning: Permanently added '10.1.2.4' (ED25519) to the list of known hosts.
bff
    inet 10.1.2.4/24 metric 100 brd 10.1.2.255 scope global eth0
status: done
Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2
salida: 135.232.207.197
default via 10.1.2.1 dev eth0 proto dhcp src 10.1.2.4 metric 100 
10.1.2.0/24 dev eth0 proto kernel scope link src 10.1.2.4 metric 100
```

La salida de bff coincide con la IP pública de gw-azure; el gateway anuncia forwarding y MASQUERADE.

## 7 · Azure: la ruta de la subred privada

```text
$ az network route-table route list -g biblioteca-l10 --route-table-name rt-privada -o table
AddressPrefix    HasBgpOverride    Name    NextHopIpAddress    NextHopType       ProvisioningState    ResourceGroup
---------------  ----------------  ------  ------------------  ----------------  -------------------  ---------------
0.0.0.0/0        False             salida  10.1.1.4            VirtualAppliance  Succeeded            biblioteca-l10
```

La ruta por defecto apunta a la IP privada del gateway como dispositivo virtual.

## 8 · Azure: las dos máquinas, desasignadas

```text
$ az vm list -d -g biblioteca-l10 --query "[].[name,privateIps,powerState]" -o table
Column1    Column2    Column3
---------  ---------  --------------
bff        10.1.2.4   VM deallocated
gw-azure   10.1.1.4   VM deallocated
```

Ambas máquinas quedaron desasignadas, con las IP privadas esperadas.
