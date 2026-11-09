# Red de la biblioteca · L9

Diseño de la red de las dos nubes, antes de crear nada. Parte de `ep3/fragmentos/e1/red.md.ejemplo`, que es el
diseño que el docente ensayó en el Learner Lab y en Azure for Students: las mismas máquinas y las mismas IP
privadas, con los nombres de la biblioteca. Lo que sigue entre `<>` es lo que cada integrante completa con sus
datos; cada tamaño lleva una línea que lo justifica.

## AWS · VPC 10.0.0.0/16 · us-east-1

| Subred | Rango | Zona | Ruta 0.0.0.0/0 |
|---|---|---|---|
| pública | 10.0.1.0/24 | us-east-1a | Internet Gateway |
| aplicación | 10.0.11.0/24 | us-east-1a | interfaz de red de `nat` |
| datos-a | 10.0.21.0/24 | us-east-1a | interfaz de red de `nat` |
| datos-b | 10.0.22.0/24 | us-east-1b | interfaz de red de `nat` |

`datos-b` está en otra zona de disponibilidad para que una falla de zona no se lleve las tres `mq`.

| Máquina | Subred | IP privada | Tamaño | Lo que corre | Por qué ese tamaño |
|---|---|---|---|---|---|
| `gw-aws` | pública | 10.0.1.20, con Elastic IP | t3.small | Caddy con HTTPS y `biblioteca-gateway` | El gateway usa 34 MiB y Caddy poco más; 2 GiB sobran, pero es la única máquina con puerto público y un t3.nano (0,5 GiB) no deja margen para el SO, Docker y Caddy |
| `nat` | pública | 10.0.1.10 | t3.nano | NAT instance de las subredes privadas | Solo reenvía paquetes, sin contenedores: 0,5 GiB bastan |
| `servicios` | aplicación | 10.0.11.10 | t3.medium | `biblioteca-libros`, `biblioteca-prestamos` y `biblioteca-eventos` | Los tres suman 175 MiB medidos (libros 21, prestamos 59, eventos 95); los 4 GiB dejan margen para los consumidores que se agregan en la E2 y para construir las imágenes en la propia máquina |
| `gestion` | aplicación | 10.0.11.20 | t3.medium | `biblioteca-admin`, Kafka UI, `biblioteca-simulador`, runner `aws` (Prometheus y Grafana, opcionales) | Kafka UI usa 394 MiB medidos, la mayor parte; admin 37 y el simulador es un proceso de Node de corta vida. Los 4 GiB dejan margen para el runner y para Prometheus y Grafana si se instalan |
| `mq-1` | datos-a | 10.0.21.11 | t3.small | controller 1, broker 4 y `rabbit1` | Controller 234 MiB, broker 316 y `rabbit1` 137 medidos: unos 690 MiB más SO y Docker caben en 2 GiB; un broker lleva su heap de 512 MiB y no entra en 1 GiB |
| `mq-2` | datos-b | 10.0.22.12 | t3.small | controller 2, broker 5 y `rabbit2` | Los mismos tres procesos que `mq-1`: controller 279 MiB, broker 447 y `rabbit2` 143 medidos, unos 870 MiB |
| `mq-3` | datos-a | 10.0.21.13 | t3.small | controller 3 y broker 6 | Controller 259 MiB y broker 336 medidos, unos 600 MiB; se deja igual que las otras dos `mq` para que los tres brokers rindan lo mismo |
| `datos` | datos-a | 10.0.21.30 | t3.small | Postgres 18 | Postgres usa 38 MiB en reposo con los esquemas de `prestamos` y `eventos`; el resto es caché de disco y 2 GiB alcanzan |

Medido en L9, con todo el sistema en Docker local y el simulador ya reproducido (`docker stats --no-stream`).
Medido en el ensayo de AWS de VidalStore: una `mq` en t3.small usa 925 de 1.909 MB con Kafka y RabbitMQ.

| Grupo de reglas | Puerto | Origen | Para qué |
|---|---|---|---|
| `sg-gw` | 80 | `0.0.0.0/0` | Desafío de Let's Encrypt y redirección a HTTPS |
| `sg-gw` | 443 | `<IP pública de gw-azure>/32` | La API, solo para el BFF |
| `sg-servicios` | 3001, 3002 y 3010 | `sg-gw` y `sg-gestion` | El gateway llega a `libros` y `prestamos`; el administrador revisa `eventos` |
| `sg-mq` | 9092 | `sg-servicios`, `sg-gestion` y `sg-mq` | Clientes de Kafka y réplica entre brokers |
| `sg-mq` | 9093 | `sg-mq` | Quórum KRaft |
| `sg-mq` | 5672 | `sg-servicios` y `sg-gestion` | AMQP de RabbitMQ |
| `sg-mq` | 15672 | `sg-gestion` | Administración de RabbitMQ |
| `sg-mq` | 4369 y 25672 | `sg-mq` | Clúster de RabbitMQ |
| `sg-datos` | 5432 | `sg-servicios` y `sg-gestion` | Postgres |
| `sg-nat` | todos | `sg-servicios`, `sg-gestion`, `sg-mq` y `sg-datos` | Salida a internet de las subredes privadas |
| `sg-gestion` | ninguno | | Se entra por Session Manager |

Ninguna regla abre el 22: se entra a todas las máquinas por Session Manager. Cada regla nombra otro
grupo como origen, salvo las dos de `sg-gw`, porque lo que llega desde fuera de la VPC no tiene grupo.

Las IP privadas son fijas porque los brokers de Kafka anuncian su dirección: si cambiara al reiniciar, los
clientes (`biblioteca-prestamos`, `biblioteca-eventos`, el simulador) no los encontrarían.

## Azure · VNet 10.1.0.0/16 · `<region>`

| Subred | Rango | Salida a internet |
|---|---|---|
| pública | 10.1.1.0/24 | directa, por la IP pública de `gw-azure` |
| privada | 10.1.2.0/24 | por `gw-azure` (tabla de rutas hacia 10.1.1.4); creada con `--default-outbound false` |

| Máquina | Subred | IP privada | Tamaño | Lo que corre | Por qué ese tamaño |
|---|---|---|---|---|---|
| `gw-azure` | pública | 10.1.1.4, con IP pública estática y etiqueta `<etiqueta>` | B2ats_v2 | Caddy, `biblioteca-web`, `biblioteca-gateway` y NAT de la subred privada | 1 GiB de RAM: nginx usa 10 MiB y el gateway 34 MiB medidos, más Caddy; en el ensayo de VidalStore, con lo mismo, la máquina veía 887 MB y le quedaban 506 libres |
| `bff` | privada | 10.1.2.4, sin IP pública | B2als_v2 | `biblioteca-bff` y el runner `azure` | El BFF usa 37 MiB medidos; los 4 GiB del B2als_v2 dejan el resto para el runner |

| NSG | Puerto | Origen | Para qué |
|---|---|---|---|
| `gw-azure` | 443 y 80 | Internet | La web y el desafío de Let's Encrypt |
| `gw-azure` | 22 | `<IP de cada integrante>/32` | SSH |
| `gw-azure` | todos | 10.1.2.0/24 | El NAT de `bff` |
| `bff` | todos | 10.1.0.0/16 | Solo desde la VNet |
