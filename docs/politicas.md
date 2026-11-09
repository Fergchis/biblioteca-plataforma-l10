# Políticas de retención · biblioteca

Viven en `rabbitmq/politicas.json` y se cargan con
`docker compose exec rabbit1 rabbitmqctl import_definitions /etc/rabbitmq/politicas.json`.
Todas con `apply-to: quorum_queues` y prioridad 1; los patrones no se superponen.

| Política | Colas | Valores | Por qué | Qué se pierde |
|---|---|---|---|---|
| `retencion-dlq` | `notificaciones.dlq`, `auditoria.dlq`, `correos.dlq` | `max-length` 1000, `message-ttl` 7 días, `overflow` `reject-publish` | Mil muertos bastan para diagnosticar; el TTL solo actúa si el consumidor de cartas muertas lleva una semana caído | Con la DLQ llena, el mensaje que iba a morir no llega a la DLQ ni a `mensajes_muertos` |
| `retencion-avisos` | `notificaciones` | `max-length` 10000, `message-ttl` 3 días, `overflow` `reject-publish` | Un aviso de hace tres días ya no sirve; al vencer cae a `notificaciones.dlq` con motivo `expired` | Los avisos vencidos no se entregan; con la cola llena, `biblioteca-prestamos` recibe el rechazo |
| `retencion-trabajo` | `auditoria`, `correos` | `max-length` 10000, `overflow` `reject-publish`, sin TTL | La auditoría es la prueba de lo que pasó y no vence; el techo protege el disco | Con la cola llena, el evento nuevo se rechaza al productor |

Una cola quorum con `reject-publish` acepta un mensaje más que su `max-length` antes de rechazar
(medido en L8 5.3). `reject-publish-dlx` no sirve en quorum: se acepta sin error y se porta como
`drop-head`.
