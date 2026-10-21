# Embudo comercial · parche n8n local

Estado actualizado 21/10/2026: parche probado y **aplicado a los tres borradores remotos, sin publicar ni ejecutar envíos**. Las versiones activas anteriores se conservaron. Referencias exactas y orden de habilitación en [RELEASE_2026_10_21.md](../RELEASE_2026_10_21.md). La lectura/base original es del 20/10/2026.

## Artefactos

`commercial-funnel-baseline.json` conserva parámetros/conexiones necesarios de las versiones publicadas, sin credenciales, clientes ni ejecuciones. `commercial-funnel-build.cjs` genera `commercial-funnel-operations.json`: operaciones incrementales con workflowId/baseVersionId/activeVersionId. `commercial-funnel-verification.json` registra validación MCP de los 17 nodos modificados, 11 pruebas de comportamiento y ESLint.

```sh
node docs/arroyo/n8n/commercial-funnel-build.cjs
node --test spec/javascript/arroyo/commercial_funnel_n8n.test.cjs
```

El generador no consulta la red ni aplica operaciones. Nodos nuevos referencian la credencial `Chatwoot - admin` por nombre; resolver su ID en destino verificando cuenta/rol, sin copiar secretos. No se altera la credencial bot del envío heredado.

## Contratos requeridos

API admin bajo `/api/v1/accounts/:account_id/arroyo/commercial`:

- GET contexts paginado, filtro opcional conversation_id (display ID): `{config:{funnel_enabled,balanced_assignment_enabled,seller_ids},contexts:[{conversation_id,opportunity_reference,state,last_client_at,last_human_at,commercial_allowed,follow_up:{sent_count,last_sent_at}}],meta:{next_page}}`. Config presente aun con lista vacía; última página next_page:null. Conteo por mensajes reales no fallidos identificados por oportunidad/paso. El backend deriva state:inactive después de tres seguimientos con entrega/lectura confirmada y espera de dos fechas locales, solo sin atención humana pendiente.
- POST assign `{conversation_id}` devuelve `{assignee_id,opportunity_reference,assigned}`. Bloqueo, idempotencia por oportunidad, respeta toma manual concurrente. assigned:false evita otro saludo personal. Ambos flags requeridos. Un error detiene la ejecución; no se reparte localmente tras timeout.
- POST follow_up/message `{conversation_id,opportunity_reference,step,content,template_params}` devuelve mensaje nativo `{id,...}`. Bloquea conversación, verifica oportunidad/turno/paso/cadencia y devuelve mensaje existente para reintento de oportunidad+paso. Backend valida plantilla Meta aprobada y renderiza variables conocidas asesor/producto. Escribe content_attributes con arroyo_kind:commercial_follow_up, arroyo_opportunity_reference y arroyo_step. No hay alternativa de texto libre ante plantilla inválida.

Bot y saludos automáticos llevan arroyo_kind y referencia de oportunidad cuando existe. El saludo personal prioriza referencia devuelta por asignación. Con flags apagados los marcadores siguen identificando automatizaciones.

## Conservación y coordinación

Flags apagados: Redis INCR/asignación nativa y clasificador publicado completo, envío por nodo bot original. Lecturas nuevas requieren backend desplegado aun con flags apagados. Embudo habilitado: contexto real por oportunidad; pendientes humanos, ventas/casos sin evidencia excluidos; no inferir respuesta desde last_activity_at. Una nueva oportunidad confirmada puede continuar aunque exista compra previa mediante commercial_allowed.

Se preservan cron comercial, dos días entre plantillas, tres nombres/plantillas Meta, domingos configurados, paginación completa de destinatarios y Postventa cada 15 minutos. Contextos paginados sin límite se reducen a una sola señal antes de buscar chats para no multiplicar llamadas. Merge heredado seguimiento_* permanece, pero bajo flag nuevo esos atributos no deciden secuencia ni clasificación.

## Despliegue posterior

1. Desplegar backend/migraciones con flags apagados y verificar endpoints/permisos en cuenta aislada.
2. Releer versiones actual/activa inmediatamente antes de actualizar. Bases: principal 4cb9c56a-acc9-45e7-b636-9ee0e0aa8929; derivación 45100a85-4f3c-474d-a029-08e6ea6f8857; seguimiento e67dc3de-e883-41ec-b93c-21c0459775df. Si difieren, revisar y regenerar. La API no ofrece CAS de versión; baseVersionId es control previo local, no argumento update_workflow.
3. Preparar un entorno aislado con URL/cuenta/credenciales de prueba; no se presupone una rama staging. Aplicar solo operations por workflow (derivación, principal, seguimiento), revisar grafo/credenciales y probar únicamente con destinatarios propios.
4. Probar flags apagados/encendidos: toma manual concurrente/reintento, saludos sin atención humana, oportunidad nueva en chat vendido, soporte sin venta, cientos de contextos/destinatarios, reintento de paso sin duplicar, plantilla fallida sin declarar silencio. Confirmar postventa 15 minutos y cadencia de dos fechas locales.
5. El usuario autorizó la integración y se encarga del despliegue del servidor. La publicación/habilitación queda pendiente de comprobar ese despliegue. Publicar parches con flags apagados primero; habilitar embudo y luego reparto al terminar pruebas. No ejecutar pruebas contra clientes.

Rollback funcional: apagar balanced_assignment_enabled/funnel_enabled; conserva historial y recupera reparto/clasificador heredados. Dejar terminar derivaciones antes de cambiar flags. Restaurar bases para retirar lecturas solo tras revisar cambios posteriores. Validación MCP es de esquema, no ejecución end-to-end ni prueba de credenciales/entrega. id/sent no demuestra delivered/read. Pendiente comprobar la integración remota y las plantillas en un entorno aislado.
