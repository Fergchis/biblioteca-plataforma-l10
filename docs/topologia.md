# Topología · biblioteca

| Exchange | Tipo | Cola | Binding | Caso de uso |
|---|---|---|---|---|
| `biblioteca.eventos` | topic | `notificaciones` | `prestamo.*` | Avisar al lector de lo que pasó con su préstamo |
| `biblioteca.eventos` | topic | `auditoria` | `#` | Guardar todo hecho en `eventos_auditoria` |
| `biblioteca.comandos` | direct | `correos` | `correo.enviar` | «Enviar» el correo y guardar la `Notificacion` |
| `biblioteca.dlx` | direct | `notificaciones.dlq` · `auditoria.dlq` · `correos.dlq` | el nombre de su cola de trabajo | Apartar lo que no se pudo procesar |

| Routing key | Quién la publica | Payload |
|---|---|---|
| `prestamo.creado` | `biblioteca-prestamos` | `{ prestamoId, libroId, usuarioSub, hasta }` |
| `prestamo.devuelto` | `biblioteca-prestamos` | `{ prestamoId, libroId, usuarioSub }` |
| `correo.enviar` | `NotificacionesConsumidor` | `{ para, asunto, cuerpo, origen, eventoId }` |

Desde L8 las seis colas se declaran con `x-queue-type: quorum` y se replican en `rabbit1` y `rabbit2`.

## Kafka (L9)

Los mismos hechos de préstamos, ahora también en un log: Kafka no reemplaza a RabbitMQ, convive con él. Los topics
los crea solo `kafka/topics.sh`: 3 particiones, 3 réplicas, `min.insync.replicas=2`, `cleanup.policy=delete`.

| Topic | Quién publica | Key | Retención | Quién lee | Tipos de evento |
|---|---|---|---|---|---|
| `biblioteca.prestamos` | `biblioteca-prestamos` (y el simulador) | `usuarioSub` | 7 días | `biblioteca-eventos`, grupo `biblioteca-panel` | `prestamo.creado` `{prestamoId, desde, hasta}`, `prestamo.devuelto` `{prestamoId}` |
| `biblioteca.lecturas` | el simulador (los lectores electrónicos) | `libroId` | 24 horas | `biblioteca-eventos`, grupo `biblioteca-panel` | `lectura.iniciada`, `lectura.terminada`, `capitulo.terminado` |
| `biblioteca.prestamos.dlt` · `biblioteca.lecturas.dlt` | (E3) | | 7 días | | Lo que no se pudo procesar |

Todo mensaje lleva el mismo sobre en JSON: `eventoId`, `tipo`, `version` (1), `emitidoEn`, `libroId` (siempre
string), `usuarioSub` y `datos`. Los headers son `x-evento-id` (igual a `eventoId`), `x-correlation-id` y
`content-type: application/json`.

Los payloads de RabbitMQ de arriba no cambiaron. La diferencia: en Kafka `prestamoId` viaja como string (el
simulador usa UUID) y `prestamo.devuelto` lleva como `usuarioSub` al dueño del préstamo, que es la key.
