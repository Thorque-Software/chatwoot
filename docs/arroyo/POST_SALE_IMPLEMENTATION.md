# Postventa Arroyo — plan de implementación

> **For agentic workers:** ejecutar por tareas usando superpowers:executing-plans. Los subtareas independientes de interfaz y workflow pueden delegarse con superpowers:dispatching-parallel-agents; no editar los mismos archivos ni publicar n8n.
**Goal:** n8n programa D1/D7/D30; Chatwoot registra compra, entrega y seguimiento manual.
**Architecture:** compra capturada desde vendido; fechas declaradas por n8n; creación idempotente por etapa mediante API Arroyo; listener/watchdog local; pestaña Postventa.
**Tech Stack:** Rails 7.1 / Ruby 3.4.4 / PostgreSQL / Sidekiq / Vue3 / n8n.
**Spec:** [POST_SALE_PLAN.md](POST_SALE_PLAN.md), aprobado por Mauro el 13/10/2026 junto con inicio de cambios.

## Estado al 13/10/2026

Código de las tareas 1–5 preparado en `arroyo/dev`; workflow guardado como borrador y probado por MCP con HTTP simulado. Verificación local: 12 pruebas Node, 15 Vitest, ESLint y análisis/sintaxis Ruby aprobados. Segunda revisión independiente sin nuevos hallazgos importantes. **Pendiente:** bundle completo, RSpec, migración/schema, comprobación visual y prueba integrada en un entorno separado con plantillas reales. Mauro solicita publicar este avance en GitHub el 13/10/2026 después de conocer estas limitaciones. La publicación en la rama de desarrollo no incluye despliegue ni activación del workflow. Las casillas siguientes conservan el desglose original de la ejecución; el estado verificado y los pasos restantes están en [POST_SALE_RUNBOOK.md](POST_SALE_RUNBOOK.md).

## Global Constraints
- Rama arroyo/dev; no cambios en enterprise ni migraciones existentes.
- Namespace Arroyo, tablas arroyo_*, hooks core con ARROYO:, es/en y Tailwind.
- post_sale.enabled apagado; defaults 10:00 todos los días, plazo entrega 6h.
- No publicar workflow ni desplegar antes de revisión; modificar solo su versión guardada.
- Sin envío automático desde Rails; el endpoint crea mensaje por pipeline nativo cuando lo pide n8n.
- Sin duplicar compra por conversación ni mensaje por compra/etapa.
- No borrar datos ajenos al escribir etiquetas/atributos.
- Cambios previos de documentación pertenecen a esta misma tarea; conservarlos.

## Review Focus
- Timeout/repetición del POST no crea segundo mensaje.
- Registro de mensaje y etapa se confirma en una misma transacción.
- Desactivación no pierde estados de mensajes que ya existían.
- Cancelación y mensajes privados no generan contacto automático indebido.
- Etapas sin programación/ejecución también deben ser visibles y alertables.

## Contrato común
Base /api/v1/accounts/:id/arroyo/post_sale.
GET purchases: {config: {enabled, timezone, send_hour_local, skip_sundays, stages, delivery_timeout_hours}, purchases: [{reference, revision, planned_revision, purchased_at, product, seller: {id,name}, conversation_id, follow_ups: [{id,stage,status,scheduled_at,message_id}]}]}.
PUT purchases/:reference/plan: {revision, stages: {d1: ISO, d7: ISO, d30: ISO}}.
PATCH purchases/:reference: {purchased_at: ISO}; incrementa revision, vacía fechas solo sin intento, audita.
GET follow_ups: {follow_ups:[{id,stage,status,scheduled_at,attempted_at,delivered_at,read_at,error_code,error_message,manual_status,alert_assignee_id,resolved_at,resolution_method,resolution_note,purchase:{reference,revision,purchased_at,product,seller:{id,name},conversation_id,contact:{id,name,phone_number}},message:{id,content,status,source_id}|null}], totals:{manual_pending, ...statusCounts}}. Filtros since/until locales, user_ids[], inbox_ids[], status, purchase_reference; <=200 resultados.
POST follow_ups/:id/message: {revision,content,template_params?,execution_id?}. Idempotente: devuelve seguimiento incluyendo message_id y estado; no reintenta fallo.
POST follow_ups/:id/resolve: {method: call|personal_whatsapp|other,note}.
POST conversations/:conversation_id/attributes: {custom_attributes:{seguimiento_envios,seguimiento_ultimo_envio,seguimiento_ultimo_envio_ts}}. Merge atómico con lock; admin de cuenta, parámetros limitados.
GET context por followup incluye can_reply, inbox.channel_type, nombre vendedor/producto para selección n8n. GET follow_ups será consumido por UI; n8n procesa los followups embebidos en purchases, enriquecidos con can_reply y estado.

Estados: awaiting_plan, scheduled, queued, sent, delivered, read, failed, unconfirmed, not_executed, cancelled.
manual_status: pending|resolved|closed_automatically|null, separado de entrega.
Usuario admin para integración; agentes ven compras propias/tareas asignadas. Sender de mensajes de postventa nil; content_attributes.arroyo_kind=post_sale y referencia/etapa.

## Task 1: Persistencia y captura
Files: nueva migración, app/models/arroyo/post_sale_purchase.rb, follow_up.rb; app/listeners/arroyo/post_sale_listener.rb; sync_dispatcher hook; specs modelos/listener.
- [ ] Specs de vendido crea tres etapas con fecha evento/vendedor original; repetir no duplica; contactos/canales excluidos; cancelaciones.
- [ ] Ejecutar specs y constatar fallo antes de código, si runtime Ruby está disponible.
- [ ] Migración dos tablas, relaciones/índices/validaciones, captura síncrona corta y cancelación.
- [ ] Verificar specs/Ruby syntax, anotar limitaciones de entorno si falta Ruby.

## Task 2: API y envío idempotente
Files: controllers/policies/services Arroyo post_sale; config/routes/arroyo.rb; spec/controllers y services.
- [ ] Specs auth/otra cuenta, agentes, fechas, revisión obsoleta, fecha corregida, POST repetido, error antes de crear mensaje.
- [ ] Implementar plan/revisión/corrección; locks y transacción al crear MessageBuilder(nil); guarda message_id antes de commit; catch error registra failed.
- [ ] Reabre resolved y restaura vendedor válido; cancelación se revalida antes del envío; sin template+ventana cerrada -> fallo explícito.
- [ ] Merge custom attrs preserva claves de otras features.
- [ ] Config defaults 10h/sundays false/mail propio false, mensajes D1/D7/D30 consulta+accesorios; validación alert recipients al activar.
- [ ] Verificar contrato con JSON de n8n/UI y specs.

## Task 3: Entrega y alertas
Files: Arroyo post_sale services reconcile/alert/resolve, delivery listener, watchdog job; async_dispatcher y schedule hooks; backend es/en.
- [ ] Specs failed, source_id sin delivered, delivered/read, eventos duplicados, late delivery, timeout, no plan/no dispatch, cancelado; conservar resolution.
- [ ] Crear nota privada con mención nativa y tarea una vez; preservar etiquetas; no cambiar assignee.
- [ ] Watchdog */30 observa existentes, no envía; alertar 6h sin confirmación o no ejecución; reconcile obtiene estado actual.
- [ ] Agregar es/en sin bare copy de UI y sin duplicar correo propio.
- [ ] Ejecutar specs nuevos y core afectados / rubocop si disponible.

## Task 4: Panel
Files owned by frontend agent: routes/dashboard/arroyo/panel/{Index.vue,constants.js,components/PostSaleTab.vue,specs/...}, arroyo/api/postSale.js, settings/components/PostSaleSection.vue; i18n locale/es/en/arroyo.json.
- [ ] Test de render, filtros, estados/errores, resolver y corregir fecha.
- [ ] Pestaña Postventa, resumen/listado/detalle, link mensaje/conversación, resolución manual y fecha de compra editable.
- [ ] Usar contrato Task2 y políticas locales; filtros existentes; mostrar errores claros.
- [ ] Copy sobre programación n8n y controles efectivos; quitar mail propio MVP.
- [ ] Vitest/eslint en tocados.

## Task 5: n8n
Files owned by n8n agent: docs/arroyo/n8n/post_sale-*.js/json/md y specs JS de transformación.
- [ ] Releer versión guardada/publicada, verificar referencias/credencial user sin secretos.
- [ ] Preparar branch n8n registro-plan-envío con rutas Task2; n8n calcula D1/7/30 calendario AR a las10, consulta configuración única.
- [ ] Idempotencia por stage ID/revision; no fallback POST nativo; manejo error sin marcar entregado.
- [ ] Preservar rama seguimiento, corregir merge attrs con ruta Arroyo; excluir compras de nueva postventa activa de seguimiento diario.
- [ ] Revisar tres templates de Meta, dejar decisiones pendientes identificadas si no están aprobadas.
- [ ] Validar nodes antes update; guardar cambios sin publicar; verificar activeVersionId/grafo producción no cambiaron.
- [ ] Pruebas locales fixture, nunca ejecutar workflow contra clientes.

## Task 6: Verificación/revisión y entrega
- [ ] Revisar diff sin enterprise/migraciones antiguas, hooks ARROYO, linters/tests disponibles.
- [ ] Revisión independiente de contrato, race conditions y scopes; corregir hallazgos.
- [ ] Documentar deploy/migraciones y activación/desactivación por cuenta, templates y pendientes de staging.
- [ ] Completar los checks Ruby requeridos antes de integrar o desplegar. Publicación del avance en `arroyo/dev` solicitada por Mauro con la limitación de entorno informada.
