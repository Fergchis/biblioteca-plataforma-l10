# Métricas del clúster · biblioteca

Se leen en la Management UI (`http://localhost:15672`) o por su API HTTP, con el usuario del `.env`:
`/api/overview`, `/api/nodes` y `/api/queues/%2F?columns=name,type,state,messages_ready,messages_unacknowledged,consumers,node`.

| Métrica | Normal en este sistema | Problema desde | Qué se hace |
|---|---|---|---|
| Colas activas (`object_totals.queues`) | 6: las de `topologia.ts` | Más de 6, o menos | Si sobran, alguien las creó a mano o el administrador tiene un error; si faltan, el worker no arrancó |
| Mensajes pendientes (`messages_ready`) | 0, o unos pocos que bajan en segundos | Crece durante minutos | Mirar `consumers`: si está en 0, el worker está caído (`docker compose ps`, `docker compose logs eventos`). No se borra la cola |
| Sin confirmar (`messages_unacknowledged`) | 0 o 1 (prefetch 1) que sube y baja | Quieto en 1 con `consumers` en 1 | Consumidor que no hace `ack` o colgado: leer su log y su código |
| Tasas de publicación y entrega | Entrega igual a publicación | Publicación mayor que entrega por un rato largo, o entrega en 0 con consumidores | Consumidor lento o trabado |
| Consumidores (`consumers`) | 1 por cola | 0 en cualquiera de las seis | Levantar o reiniciar el worker |
| Mensajes en las DLQ (`messages_ready` de las `.dlq` y filas de `mensajes_muertos`) | 0 en la cola; filas nuevas solo con payloads rotos | `messages_ready` distinto de 0 en una `.dlq` | El consumidor de cartas muertas no consume: revisar el worker y Postgres. Cada fila nueva de `mensajes_muertos` se revisa por su motivo |

La alerta automática: `messages_ready` creciendo con `consumers` en 0, porque es la única falla
silenciosa. Con un nodo caído las seis colas pasan a `state: minority` en `/api/queues` y
`rabbitmq-diagnostics check_if_node_is_quorum_critical` lo anticipa.
