# Embudo comercial Arroyo — plan de implementación

> **For agentic workers:** Use superpowers:executing-plans for the backend and superpowers:dispatching-parallel-agents only for independent UI and n8n artifact tasks with the contracts below. Steps use checkbox syntax.

**Goal:** implementar el diseño aprobado de embudo, atención humana, reparto y recompra en local sobre arroyo/dev.
**Architecture:** oportunidades/eventos Arroyo persistentes; listener síncrono con origen; reporte separado del legado; asignación transaccional en Chatwoot; n8n conserva los envíos.
**Tech Stack:** Rails/PostgreSQL, Vue 3/Tailwind/i18n, n8n Code/HTTP, RSpec/Vitest/Node.
**Spec:** [SALES_FUNNEL_DESIGN.md](SALES_FUNNEL_DESIGN.md), aprobado por Mauro el 20/10 con instrucción explícita de implementar.

## Global Constraints

- America/Argentina/Buenos_Aires; 4 horas laborables, lunes-sábado 08:30–12:00 y 16:30–20:30.
- Facturación fuera de alcance; Meta exclusiva; seguimiento comercial cada dos días.
- Flags por cuenta apagados por defecto; conservar contratos y comportamiento anterior con flags apagados.
- Namespace Arroyo; no editar migraciones históricas ni enterprise; hooks core marcados ARROYO.
- Pruebas y demostración local; no publicar producción en esta etapa.

## Review Focus

1. Automatización con emisor User no es atención: marcador explícito y origen de eventos.
2. Reasignación y respuestas de dos agentes no duplican consultas/ventas; ventas conservan autor.
3. Reintento y toma manual concurrente no reasignan ni duplican oportunidades.
4. Recompra no cancela la venta anterior ni crea postventa retroactiva.
5. Permisos aplicados a totales, exportación, acciones y listados, no solo a la UI.

## Contratos compartidos

Flags/config en agent_panel: funnel_enabled:false, balanced_assignment_enabled:false, seller_ids:[], response_hours:4, lookback_days:7. Exponer en features y ajustes.

API bajo /api/v1/accounts/:account_id/arroyo/commercial:

- GET report: mismos filtros since/until/group_by/user_ids/inbox_ids del panel actual. Respuesta `{version:2, timezone, as_of, since, until, group_by, totals, agents, series, activity_totals, coverage}`. Totals contiene received, bot, unassigned, pending, attended, in_progress, won, lost, inactive, unknown, overdue, repeat_sales, post_sale_replies, post_sale_issues. agents contiene `{id,name,totals,periods:{date:{received,assigned,attended,won}}}`. series contiene `{date,received,assigned,attended,won}`. coverage contiene complete/partial.
- GET opportunities: filtros anteriores + metric, scope(cohort|activity), page; respuesta `{opportunities:[{id,reference,started_at,state,overdue,coverage,assignee:{id,name}|null,conversation:{id,display_id,contact,inbox,assignee,last_message,last_activity_at,status}}],meta:{total,next_page}}`. metric: received, bot, unassigned, pending, attended, in_progress, won, lost, inactive, unknown, overdue, repeat_sales, post_sale_replies, post_sale_issues o assigned (actividad).
- POST opportunities: conversation_id es display_id, request_key y product opcional; nueva oportunidad confirmada, idempotente, permiso sobre conversación.
- PATCH opportunities/:id: outcome=won|lost|resume, product opcional; respuesta `{opportunity:...}`. Historial/auditoría siempre; venta no duplica compra.
- GET export: CSV de las mismas métricas/filtros del nuevo reporte.
- POST assign: solo administrador, conversation_id/display_id; usa oportunidad activa y seller_ids configurados. Respuesta `{assignee_id,opportunity_reference,assigned:boolean}`; asignación manual existente se respeta. Idempotencia por oportunidad, reparto atómico con lock de cuenta.
- GET contexts: solo administrador, paginado (200), `{contexts:[{conversation_id,opportunity_reference,state,last_client_at,last_human_at,commercial_allowed}],meta}`. conversation_id es display_id, timestamps ISO o null. Incluye la oportunidad más reciente por conversación. Los mensajes automáticos se marcan content_attributes.arroyo_kind y arroyo_opportunity_reference.

## Tareas

### 1. Registro y calendario
- [x] Escribir y ejecutar en RED spec/services/arroyo/commercial/lifecycle_spec.rb y business_calendar_spec.rb: deduplicación, humano vs automatización, horario, transferencia, resultado y recompra.
- [x] Crear migración aditiva, Opportunity/Event, BusinessCalendar, Lifecycle y listener síncrono Arroyo; capturar mensajes, asignaciones y etiquetas. Ledger y proyección bajo lock.
- [x] Ejecutar RSpec hasta GREEN y revisar hooks core afectados.

### 2. Reporte, permisos y asignación
- [x] Escribir RED spec/controllers/api/v1/accounts/arroyo/commercial_controller_spec.rb (incluye asignación): filtros, medianoche, cohort/actividad, vendedor restringido, reintentos/tomas manuales.
- [x] Implementar Report, Query, Presenter, AssignmentService, controller y rutas según contratos. Nueva configuración validada y flags.
- [x] Ejecutar nuevas specs y las existentes de settings/features/panel/postventa hasta GREEN.

### 3. Panel (unidad independiente tras fijar contratos)
- [x] Escribir RED pruebas del nuevo FunnelTab; implementar gráfico accesible con componentes existentes y tablas/listado paginado/acciones, ayuda contextual, exportación y configuración.
- [x] Integrar en Actividad mediante flag, conservar reporte legado y pestañas Seguimientos/Postventa. Traducciones es/en sin textos hardcodeados.
- [x] Vitest y ESLint de archivos tocados hasta GREEN.

### 4. n8n (artefacto independiente, sin publicación)
- [x] Escribir RED pruebas Node del generador contra fixture del workflow actual: asignación backend, marcadores automáticos, respuesta entrante real, coordinación por oportunidad y cadencia intacta.
- [x] Generar parche incremental local para derivación/principal/seguimientos, con baseVersionId y contratos anteriores; flags/aprobación de deploy antes de aplicar. Sin modificar credenciales ni activar envíos.
- [x] Node tests GREEN; validación MCP de configuraciones preparadas donde aplique. Documentar orden de publicación.

### 5. Demostración y verificación
- [x] Reconstrucción explícita solo de hechos comprobables, cobertura parcial, sin enviar ni reasignar. Fixtures locales sintéticos para los estados y dos compras.
- [x] Migrar base local, sincronizar fuentes al runtime aislado y habilitar solo flags locales. Primera inspección de escritorio y pruebas de acciones/API automatizadas realizadas.
- [ ] Completar la pasada visual final de escritorio/móvil: navegador local deshabilitado en Work. Ver runbook.
- [x] RSpec/RuboCop/ESLint/Vitest/Node de cambios y regresiones afectadas; revisión independiente final; documentar límites y estado de publicación.

La instrucción «Sí, lo apruebo. Implementalo» autoriza ejecutar este desglose técnico del diseño, sin otra ronda de permiso para el mismo alcance. La publicación remota continúa separada.
