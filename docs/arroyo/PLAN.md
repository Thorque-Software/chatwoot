# Plan Chatwoot Arroyo — instrucciones para Claude Code

> Diseño comercial 20/10/2026: la ampliación del Panel de vendedores, las reglas de atención y atribución, el reparto con historial y la recompra se especifican en [SALES_FUNNEL_DESIGN.md](SALES_FUNNEL_DESIGN.md). Propuesta conversacional aprobada; especificación escrita pendiente de revisión. Facturación queda fuera de esta etapa. No modifica aún el comportamiento publicado.

> Actualización 20/10/2026: el pedido de plantillas exclusivas reemplaza la selección de texto libre según ventana descrita más abajo. Postventa siempre usa `postventa_d1/d7/d30`; el detalle vigente está en `n8n/TEMPLATE_ONLY.md`. El recordatorio editable de 24 h se retira de Ajustes; se conserva la consulta de ventanas.

> Uso: este archivo vive en el repo como `docs/arroyo/PLAN.md`. La sección "Reglas del fork" está copiada en el `CLAUDE.md` de la raíz. Pedile a Claude Code las fases de a una: *"Leé docs/arroyo/PLAN.md y hacé la Fase 0"*, revisás, commit, siguiente fase.
>
> Las diferencias entre este plan y el código real (v4.14.2) están en `docs/arroyo/ARCHITECTURE_NOTES.md`, sección "Diferencias contra el plan". Ante contradicción, manda ARCHITECTURE_NOTES.

---

## Reglas del fork (pegar en CLAUDE.md)

```
# Fork Chatwoot Arroyo — reglas

- Este repo es un fork de chatwoot/chatwoot para el cliente Arroyo Fitness.
  Prod: https://chatarroyo.thorque.com.ar. NO romper funcionalidad nativa.
- Todo código nuevo vive en el namespace Arroyo:
  app/models/arroyo/, app/services/arroyo/, app/jobs/arroyo/, app/listeners/arroyo/,
  app/controllers/api/v1/accounts/arroyo/, app/policies/arroyo/,
  app/javascript/dashboard/routes/dashboard/arroyo/, spec/**/arroyo/
  Tablas con prefijo arroyo_.
- Archivos core de Chatwoot: tocarlos SOLO cuando el plan lo indica (hooks puntuales).
  Cada cambio en un archivo core lleva el comentario `ARROYO:` (en Ruby `# ARROYO:`,
  en Vue/JS `// ARROYO:`) para poder listarlos con `git grep "ARROYO:"`.
- Nunca editar migraciones existentes ni nada dentro de enterprise/.
- No borrar features nativas: si algo se "reemplaza", se oculta del sidebar, no se elimina.
- Cada feature tiene un flag por cuenta en Arroyo::Setting y viene APAGADA por defecto.
- Antes de commitear: bundle exec rspec (specs nuevos + specs core afectados),
  bundle exec rubocop en archivos tocados, pnpm eslint en archivos tocados.
- Si una suposición del plan no coincide con el código real, PARAR, anotarlo en
  docs/arroyo/ARCHITECTURE_NOTES.md y proponer alternativa antes de seguir.
- Zona horaria del negocio: America/Argentina/Buenos_Aires.
- Textos de UI en i18n (es y en), nunca hardcodeados.
```

---

## Fase 0 — Exploración y verificación (sin escribir features)

Objetivo: que Claude Code confirme con el código real todo lo que este plan supone, porque Chatwoot cambia bastante entre versiones.

1. Confirmar la versión de Chatwoot del fork y que coincida con la que corre en prod (`git describe --tags`, y en prod el footer/`/api` o la imagen docker). **Si el fork salió de `develop` y prod corre otra versión, rebasar sobre el tag de prod.** Un upgrade involuntario de Chatwoot es la forma más fácil de romper todo.
2. Configurar remote `upstream` y trabajar en branch `arroyo/main`.
3. Relevar y documentar en `docs/arroyo/ARCHITECTURE_NOTES.md` (clase, archivo, cómo se usa):
   - Event dispatcher y registro de listeners (`app/dispatchers/*`, `app/listeners/*`). ¿Qué eventos existen? En particular: message created, message updated (¿se dispara al cambiar `status`?), conversation updated / labels cambiadas.
   - Lógica de ventana de 24 hs (buscar `can_reply`, `MessageWindowService` o similar) para WhatsApp e Instagram.
   - Procesamiento de status webhooks de WhatsApp Cloud: dónde se setea `message.status` (sent/delivered/read/failed) y dónde se guarda el error de Meta (`external_error` u otro). Qué formato tiene el código de error guardado.
   - Envío de templates de WhatsApp: cómo se crea un mensaje con `template_params` para que salga por el pipeline normal (SendReplyJob / provider service).
   - Soporte de mensajes interactivos (`content_type: input_select` → botones de WhatsApp).
   - Soporte de `HUMAN_AGENT` tag para Instagram/Messenger (ventana extendida a 7 días). Existe como config de instalación en algunas versiones: verificar.
   - Scheduler: `config/schedule.yml` (sidekiq-cron) y formato de las entradas.
   - Canal de email: cómo `ConversationReplyMailer` elige SMTP propio del inbox vs. OAuth (Google/Microsoft) vs. SMTP global. Ese mecanismo se va a reutilizar.
   - Filtros/segmentos de contactos guardados (`custom_filters` con tipo contact).
   - Menciones en notas privadas (formato `mention://user/ID/Nombre`) y cómo generan notificación.
   - Frontend: dónde se definen las rutas de reportes y el sidebar (`components-next/sidebar` o equivalente), qué librería de gráficos usa, componentes reutilizables (tablas, date range picker, filtros de agente).
   - Tabla `reporting_events`: tipos de evento que existen y columnas (`user_id`, `value`, `event_start_time`...).
   - Índices de `messages` y `conversations` relevantes para consultas por `account_id` + rango de fechas.
4. Revisar cómo el bot de n8n se engancha (agent bot / webhook) y bajo qué condición responde, para que los mensajes automáticos nuevos no lo disparen.
5. Entregable: `ARCHITECTURE_NOTES.md` + lista de diferencias contra este plan. **No seguir a Fase 1 sin revisión.**

---

## Fase 1 — Base común

- Migración `arroyo_settings`: `account_id` (único), `config` jsonb, timestamps.
- Modelo `Arroyo::Setting` con defaults y accessors. Estructura sugerida del config:

```json
{
  "timezone": "America/Argentina/Buenos_Aires",
  "window_keeper": {
    "enabled": false,
    "nudge_after_hours": 22,
    "only_statuses": ["open"],
    "only_assigned": true,
    "nudge_text": "Hola {{contact.first_name}}, ¿pudiste ver lo que te pasamos? Si querés seguimos por acá 👇",
    "nudge_buttons": ["Sí, sigamos", "Ya lo resolví"],
    "skip_labels": ["no-contactar", "venta-perdida"],
    "reengagement_template": null
  },
  "post_sale": {
    "enabled": false,
    "trigger_label": "vendido",
    "send_hour_local": 11,
    "skip_sundays": true,
    "stages": {
      "d1":  { "days": 1,  "free_text": "...", "template": "postventa_d1" },
      "d7":  { "days": 7,  "free_text": "...", "template": "postventa_d7" },
      "d30": { "days": 30, "free_text": "...", "template": "postventa_d30" }
    },
    "delivery_timeout_hours": 6,
    "alert_user_ids": [],
    "alert_email": true
  },
  "agent_panel": { "enabled": false, "agents_see_only_own": true, "hide_native_reports": false },
  "email_marketing": { "enabled": false, "max_per_hour": 100, "max_per_day": 400, "footer_html": "" }
}
```

- Endpoint `GET/PATCH /api/v1/accounts/:account_id/arroyo/settings` (solo administradores, policy Pundit).
- Pantalla simple en Configuración → "Arroyo" para editar estos valores (formulario por sección; no hace falta editor JSON).
- Specs: modelo (defaults, merge), policy, request spec del endpoint.

---

## Fase 2 — Ventana de 24 hs (punto 1)

### Restricción de Meta (leer antes de implementar)
La ventana de 24 hs **solo se reabre cuando el cliente escribe**. Un mensaje del negocio no la extiende. Lo único posible es: antes de que cierre, mandar un mensaje que invite a responder (con botones, para que responder sea un toque). Si el cliente no responde, la ventana cierra igual y desde ahí solo se puede escribir con templates aprobados (pagos). Además, mandar nudges repetidos baja la calidad del número: **máximo un nudge por ventana**.

### Implementación
- Job `Arroyo::WindowKeeper::ScanJob` cada 10 min (entrada en `config/schedule.yml`, `# ARROYO:`).
- Selección de conversaciones de inboxes WhatsApp de la cuenta con feature activa, donde:
  - el último mensaje **entrante** fue hace entre `nudge_after_hours` y 23 h 45 min,
  - status dentro de `only_statuses`, y si `only_assigned`, con asignado,
  - no tiene labels de `skip_labels`,
  - no se mandó nudge después de ese último mensaje entrante (guardar `additional_attributes.arroyo_last_nudge_at`),
  - el último mensaje de la conversación no es ya un nudge.
- `Arroyo::WindowKeeper::NudgeService`: crea mensaje saliente no privado, `content_type: input_select` con los botones (verificar en Fase 0 que salga como botones interactivos en WhatsApp; si no, texto plano), `content_attributes.arroyo_kind = "nudge"`. Renderizar `nudge_text` con Liquid (Chatwoot ya usa Liquid en variables de mensajes).
- El mensaje debe salir por el pipeline normal para que quede en el historial y los vendedores lo vean.
- Que el bot de n8n ignore mensajes con `arroyo_kind` presente y que la respuesta del cliente al botón no lo active (según lo relevado en Fase 0; puede requerir un ajuste del lado de n8n, anotarlo).
- Al cerrar la ventana sin respuesta: aplicar label `ventana-cerrada` (job que corre en el mismo scan, para conversaciones con último entrante > 24 h sin el label). Se saca automáticamente cuando el cliente vuelve a escribir (listener de message created entrante).
- Si `reengagement_template` está configurado: opción de enviarlo automáticamente al cerrar la ventana. Viene en `null` por defecto (cuesta plata y requiere template aprobado).
- Instagram: si la versión soporta `HUMAN_AGENT`, documentar cómo activarlo (extiende a 7 días para respuestas humanas) en vez de nudges.

### Specs
- Selección: casos dentro/fuera de rango, ya nudgeado, labels excluidas, status, sin asignar, conversación de otro canal.
- Idempotencia: correr el scan dos veces no manda dos nudges.
- Label `ventana-cerrada` se pone y se saca.
- Usar `travel_to` para el tiempo.

---

## Fase 3 — Post-venta con verificación de entrega (punto 5)

> **Revisión solicitada el 2026-10-13:** n8n conserva programación y envío D1/D7/D30;
> Chatwoot registra seguimientos, verifica entrega y muestra alertas/resolución en
> el panel de vendedores. La fecha confirmada es la aplicación de `vendido`,
> corregible si se cargó tarde. La propuesta está en
> [POST_SALE_PLAN.md](POST_SALE_PLAN.md). El diseño original de abajo es histórico:
> no implementar su DispatchJob/SendService ni activar un segundo emisor mientras
> se revisa el nuevo reparto.

### Disparador de "compra"
Por defecto: el vendedor aplica la label `vendido` a la conversación (se puede armar una macro nativa "Registrar venta" que ponga la label y pida producto). Opcionalmente atributos personalizados de contacto `producto_comprado` y `fecha_compra`; si `fecha_compra` existe se usa como base, si no, la hora en que se puso la label.

### Modelo
Migración `arroyo_follow_ups`:
`account_id, contact_id, conversation_id, inbox_id, seller_id (asignado al momento de la compra), stage (d1|d7|d30), scheduled_at, status (pending|sending|sent|delivered|read|failed|undelivered|alerted|resolved|cancelled), message_id, channel_used (free_text|template), error_code, error_message, alerted_at, alert_assignee_id, resolved_by_id, resolved_at, resolution_note, product`.
Índices: `(status, scheduled_at)`, `(account_id, status)`, `message_id`. Único `(conversation_id, stage, purchase_ref)` para no duplicar si la label se pone dos veces.

### Flujo
1. Listener `Arroyo::PostSaleListener` (registrado en el dispatcher con `# ARROYO:`): cuando se agrega la label `trigger_label`, crea los 3 follow-ups con `scheduled_at` = fecha de compra + N días a `send_hour_local` (hora AR), corriendo domingos a lunes si `skip_sundays`.
2. `Arroyo::FollowUps::DispatchJob` cada 5 min toma los `pending` vencidos (con lock para no duplicar).
3. `Arroyo::FollowUps::SendService`:
   - Si el contacto tiene label `no-contactar` → `cancelled`.
   - Si la ventana está abierta → mensaje de texto libre (`free_text`).
   - Si está cerrada → template de la etapa (categoría **Marketing**, porque ofrece accesorios). Si no hay template configurado o aprobado → **alerta directa**, no se intenta enviar.
   - Contacto sin WhatsApp (ej. solo Instagram, sin teléfono) y ventana cerrada → alerta directa.
   - Guarda `message_id`, pasa a `sent`. Si el envío tira excepción antes de llegar a Meta → `failed` + alerta.
4. Verificación de entrega — listener de cambios de status del mensaje (o hook en el procesamiento de status de WhatsApp si no hay evento, con `# ARROYO:`):
   - `delivered` / `read` → actualizar follow-up. Fin feliz.
   - `failed` → guardar código de Meta y alertar. Códigos a mapear con texto humano en la alerta:
     - `131047` → ventana de 24 hs cerrada (no debería pasar si usamos template, pero cubrirlo)
     - `131049` → Meta no entregó el marketing para cuidar la experiencia del usuario (límite por usuario)
     - `131050` → el usuario se dio de baja de mensajes de marketing
     - `131026` → no se pudo entregar (número sin WhatsApp, bloqueo, versión vieja)
     - `132xxx` → problema con el template (pausado, parámetros)
     - otros → texto genérico + código
   - Watchdog `Arroyo::FollowUps::DeliveryWatchdogJob` cada 30 min: follow-ups en `sent` sin `delivered` después de `delivery_timeout_hours` → `undelivered` + alerta.
5. `Arroyo::Alerts::CreateService`:
   - Nota privada en la conversación con mención a Julieta y Marcos (`alert_user_ids`), que genera notificación nativa. Contenido: etapa, producto, motivo en castellano, código de Meta, teléfono del cliente, vendedor original.
   - Label `seguimiento-manual`.
   - Asignar la conversación al responsable de alertas (round robin entre `alert_user_ids`) **sin** sacarla del vendedor si la config lo prefiere (dejar opción).
   - Si `alert_email`, mail a cada responsable (mailer simple usando el SMTP global de la instalación).
   - Estado `alerted`.
6. Resolución manual: desde el panel (Fase 4) "Marcar como resuelta" con nota ("llamé", "le escribí por WhatsApp personal", "no atiende") → `resolved`, saca label `seguimiento-manual`.
7. Si la conversación tiene label `venta-cancelada` o se saca `vendido` → cancelar pendientes.

### Templates a crear y aprobar en Meta (fuera del código, hacerlo YA porque tarda)
`postventa_d1`, `postventa_d7`, `postventa_d30` (Marketing, con variable de nombre y producto). Opcional `seguimiento_consulta` para re-engagement.

### Specs
- Creación de los 3 follow-ups al poner label, sin duplicar.
- Cálculo de `scheduled_at` con zona horaria y salto de domingo.
- Elección texto libre vs. template según ventana.
- Cada código de error → alerta con texto correcto.
- Watchdog.
- Alerta: nota privada con menciones, label, asignación, email (ActionMailer test).
- Cancelaciones.

---

## Fase 4 — Panel de vendedores (puntos 2 y 3, reemplaza reportes)

### Backend
`GET /api/v1/accounts/:account_id/arroyo/agent_panel`
Params: `since`, `until` (fechas locales), `user_ids[]`, `inbox_ids[]`, `group_by=day|week`.
Respuesta: por vendedor y por día:

| Métrica | Definición |
|---|---|
| Consultas atendidas | conversaciones distintas donde el vendedor mandó ≥1 mensaje saliente no privado ese día (excluir mensajes con `arroyo_kind` y mensajes de bot) |
| Conversaciones nuevas asignadas | asignaciones recibidas ese día |
| Mensajes enviados | salientes no privados del vendedor |
| Tiempo de primera respuesta (mediana) | `reporting_events` de first response |
| Ventanas cerradas sin respuesta | conversaciones suyas que recibieron label `ventana-cerrada` ese día |
| Ventas registradas | label `vendido` aplicada en conversaciones suyas |
| Alertas post-venta | generadas / resueltas / pendientes |

- Agrupar por día con `AT TIME ZONE` de la config, no UTC.
- `GET .../agent_panel/conversations?user_id&date&metric` → lista para drill-down (id, contacto, inbox, último mensaje, link). Esto es lo que evita entrar conversación por conversación.
- `GET .../agent_panel/export.csv` con los mismos filtros.
- Permisos: admin ve todo; agente ve solo lo suyo si `agents_see_only_own`.
- Performance: todas las queries filtradas por `account_id` y rango. Si faltan índices, migración con `disable_ddl_transaction!` y `algorithm: :concurrently`. Probar con un dataset grande en dev (seed de ~50k mensajes) y medir.

### Frontend
- Ruta `/app/accounts/:accountId/arroyo/panel`.
- Filtros arriba: rango de fechas (presets: hoy, ayer, últimos 7, este mes, mes pasado), vendedores (multi), inbox. Filtros en la URL (query params) para poder compartir el link.
- Tarjetas de totales del período.
- Tabla vendedor × día con "consultas atendidas" (celda clickeable → drill-down en panel lateral).
- Gráfico de barras por vendedor.
- Pestaña "Post-venta": follow-ups programados, enviados, entregados, alertas pendientes con botón resolver.
- Pestaña "Ventanas": conversaciones con ventana por cerrar en las próximas horas y cerradas hoy.
- Sidebar: entrada "Panel" donde estaba "Reportes". Si `hide_native_reports`, ocultar el ítem nativo; la ruta nativa **sigue existiendo** (no borrar código ni rutas).
- Reutilizar componentes existentes de Chatwoot (relevados en Fase 0) para que se vea nativo, modo claro/oscuro incluido.

### Specs
- Request specs de cada métrica con datos armados con factories, incluyendo bordes de día en hora AR (mensaje a las 23:30 AR = otro día en UTC).
- Permisos agente vs. admin.
- Test de componente para filtros y drill-down (vitest).

---

## Fase 5 — Email marketing (punto 4, sección aparte)

### Concepto
Sección "Email marketing" en el sidebar. Para enviar se elige un **inbox de Email ya configurado en Chatwoot**; se envía usando la misma configuración de salida de ese inbox (SMTP propio u OAuth Google/Microsoft), reutilizando el mecanismo de `ConversationReplyMailer` relevado en Fase 0. Las respuestas de los clientes entran a ese inbox como conversaciones normales (Reply-To = dirección del inbox). No se crea una conversación por cada mail enviado.

### Modelos
- `arroyo_email_campaigns`: `account_id, inbox_id, title, subject, preheader, body_html, body_text, audience (jsonb: labels incluidas/excluidas, custom_filter_id), status (draft|scheduled|sending|paused|sent|cancelled), scheduled_at, started_at, finished_at, created_by_id, stats (jsonb)`.
- `arroyo_email_campaign_recipients`: `campaign_id, contact_id, email, status (queued|sent|failed|skipped_unsubscribed|skipped_invalid), sent_at, error, unsubscribe_token`. Único `(campaign_id, email)`.
- `arroyo_email_unsubscribes`: `account_id, email, unsubscribed_at, campaign_id`. Único `(account_id, email)`.

### Envío
- Al lanzar: congelar audiencia en `recipients` (deduplicado, sin emails inválidos, sin dados de baja).
- `Arroyo::EmailCampaigns::SendBatchJob` con throttle según `max_per_hour` / `max_per_day` (reprograma el resto). Pausable.
- Mailer `Arroyo::CampaignMailer`: multipart HTML + texto, variables Liquid (`{{contact.name}}`, `{{contact.first_name}}`), footer con razón social y link de baja.
- Headers obligatorios: `List-Unsubscribe: <https://.../arroyo/unsubscribe/TOKEN>, <mailto:...>` y `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (requisito de Gmail/Yahoo para envíos masivos).
- Controller público `/arroyo/unsubscribe/:token` (GET muestra confirmación, POST da de baja; el POST one-click funciona sin login). Además setea en el contacto un atributo `email_marketing_opt_out`.
- Botón "Enviar prueba" a una dirección.
- Errores SMTP por destinatario quedan en `recipients.error`; si hay muchos errores seguidos (ej. 10), pausar campaña y avisar.

### UI
- Listado de campañas con estado y stats (enviados / fallidos / bajas).
- Editor: asunto, preheader, cuerpo HTML con vista previa (empezar con editor HTML + preview; editor visual queda para después), selector de inbox (solo inboxes de email), audiencia por labels o segmento guardado, conteo estimado de destinatarios, programar o enviar ahora.

### Advertencias para el cliente (no son código)
- El dominio del mail debe tener SPF, DKIM y DMARC bien configurados o los mails van a spam.
- Una casilla de Gmail/Workspace o similar tiene límites diarios de envío bajos; para volúmenes grandes conviene un proveedor transaccional. Por eso los límites son configurables.
- Solo enviar a contactos que dieron su email con consentimiento.

### Specs
- Armado de audiencia (labels, segmento, exclusión de bajas, deduplicado).
- Throttle y reprogramación.
- Headers List-Unsubscribe presentes; unsubscribe one-click.
- Uso del SMTP del inbox elegido (verificar `delivery_method_options`).
- Pausa automática por errores.

---

## Fase 6 — Testing integral

### Local
- Levantar entorno de desarrollo de Chatwoot (docker compose de desarrollo del repo o setup local con Postgres + Redis + Sidekiq).
- `bundle exec rspec spec` completo al menos una vez antes de cada merge a `arroyo/main` (no solo los specs nuevos: es la forma de saber que no rompimos nada nativo).
- Mails en dev: letter_opener / mailhog, según lo que traiga el entorno.

### Simulaciones (dejar scripts en `script/arroyo/` o rake tasks `arroyo:simulate:*`)
- `arroyo:simulate:window CONVERSATION_ID HOURS_AGO=22.5` → mueve el último mensaje entrante en el tiempo y corre el scan.
- `arroyo:simulate:purchase CONVERSATION_ID` → pone label `vendido` y adelanta los follow-ups para que venzan ya.
- `arroyo:simulate:whatsapp_status MESSAGE_ID STATUS=failed CODE=131047` → hace POST al endpoint de webhook de WhatsApp de Chatwoot con un payload real de status (fixture JSON en `spec/fixtures/arroyo/`), así se prueba el camino completo de webhook → status → alerta.
- `arroyo:seed:panel` → genera vendedores, conversaciones y mensajes en varios días para probar el panel.

### Con WhatsApp real (staging)
- Número de prueba de WhatsApp Cloud API (Meta lo da gratis, con hasta 5 números destinatarios) conectado a un inbox en staging.
- Probar: nudge con botones, respuesta al botón (que el bot no salte), template post-venta, y un fallo real (ej. bloquear el número de negocio desde el teléfono destinatario y mandar).

### Deploy
- Staging primero, con dump de la base de prod.
- Backup de la base de prod antes de correr migraciones en prod.
- Imagen docker propia construida desde el fork, con tag fijo.
- Features se activan de a una por cuenta desde Configuración → Arroyo.

---

## Orden recomendado
0 → 1 → 4 (panel, bajo riesgo y alto valor visible) → 2 → 3 → 5 → 6 (los tests van dentro de cada fase; la 6 es la pasada integral).
Mientras tanto, pedir a Arroyo que cree y apruebe los templates de Meta.
