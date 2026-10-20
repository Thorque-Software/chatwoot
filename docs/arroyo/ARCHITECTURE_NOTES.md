# Arroyo — Notas de arquitectura (Fase 0)

Relevamiento del código de Chatwoot **v4.14.2** (la versión que corre en prod) para validar las suposiciones de `PLAN.md`.
Las rutas son relativas a la raíz del repo y los números de línea corresponden a ese tag.

## Actualización de integración n8n v3 (2026-10-13)

El relevamiento actual de los cuatro workflows publicados de la carpeta Arroyo/v3
está en [N8N_V3_ANALYSIS.md](N8N_V3_ANALYSIS.md). Esa revisión complementa y actualiza
la sección 14, que describe el bot v2. Se consultaron definiciones publicadas y
metadatos de ejecuciones; no se ejecutaron ni modificaron workflows.

Decisión del usuario para la próxima Fase 3: **n8n programa y envía D1/D7/D30;
Chatwoot verifica entrega y gestiona alertas en el panel**. La fecha de compra es
la aplicación de `vendido`, corregible si se cargó tarde. El borrador de diseño
está en [POST_SALE_PLAN.md](POST_SALE_PLAN.md); sus reglas operativas y nuevos
hooks core se proponen para revisión antes de implementación.

Diferencias contra las suposiciones del plan que deben resolverse antes de implementar:

- El bot actual v3 usa reglas y textos fijos: saluda, pregunta localidad y deriva a
  Julieta o Marcos. No vende ni usa IA. Conserva el filtro de entrantes en `pending`.
- La postventa ya está automatizada fuera del fork: n8n procesa `vendido` para
  recompra D+1 y seguimiento D+30 de la zona local, con plantillas según rubro.
  Usa `conversation.created_at` como fecha base y el asignado actual como vendedor.
  El plan propone fecha de compra/aplicación de etiqueta, vendedor original y D1/D7/D30.
- Existe además seguimiento comercial con la etiqueta `seguimiento`: hasta tres
  envíos en días habilitados. `seg_dia_1`, `seg_dia_3` y `seg_dia_5` son nombres de
  plantillas elegidas por número de envío; no implementan intervalos de 1/3/5 días.
- `Arroyo::Setting` no controla estos procesos externos. Activar una implementación
  nueva sin una transición explícita puede duplicar mensajes a los mismos clientes.
- Los dos envíos n8n incluyen `template_params`: el servicio nativo de WhatsApp
  prioriza la plantilla incluso con ventana abierta. El campo `content` no activa
  por sí solo una alternativa de texto libre.
- La rama postventa etiqueta después de intentar crear el mensaje, incluso si el
  nodo de envío continúa tras un error. La rama diaria comprueba el `id` creado,
  pero ninguna comprueba `delivered`/`read` ni ejecuta un watchdog de entrega.
- El endpoint de atributos de conversación reemplaza el hash completo. Los nodos
  diarios de n8n escriben solamente tres atributos `seguimiento_*`, por lo que
  pueden eliminar atributos ajenos. El endpoint de etiquetas también reemplaza
  el conjunto; ambos procesos deben preservar datos y evitar escrituras concurrentes.

Alternativa propuesta para revisión: mantener n8n como responsable de los envíos
durante la preparación del fork y acordar la transición por automatización/cuenta,
preservando etiquetas, contadores y plantillas existentes. Antes de activar la
Fase 3, reconciliar fecha de compra, etapas, rubros, zona, vendedor, historial y
verificación de entrega. Esta nota registra el desajuste; no cambia el plan ni
autoriza una migración o cambios de producción.

---

## 0. Versión y branches

| | Valor |
|---|---|
| Prod (`GET https://chatarroyo.thorque.com.ar/api`, 2026-10-06) | `4.14.2` |
| `origin/develop` del fork al empezar | `4.18.0` (618 commits por delante de `v4.14.2`) |
| Commits propios del fork | **0** (idéntico a `upstream/develop`) |

- Remote `upstream` = `https://github.com/chatwoot/chatwoot.git` (tags bajados).
- Branch de trabajo: **`arroyo/main`, creada desde el tag `v4.14.2`**. No hizo falta rebase porque el fork no tenía commits propios.
- `develop` queda tal cual. **No mergear `develop` ni `upstream/develop` en `arroyo/main`**: equivale a pasar prod de 4.14.2 a 4.18+ sin querer.
- Upgrades futuros de Chatwoot: `git merge vX.Y.Z` (tag puntual) en un branch aparte, con `git grep "ARROYO:"` para revisar los hooks.
- Ruby `3.4.4`. Última migración del tag: `20260525093000_change_captain_document_external_link_to_text.rb`.
- **Edición:** prod va a correr una imagen construida desde `arroyo/main`. Como el repo incluye `enterprise/`, el código EE queda **activo** (`ChatwootApp.enterprise?` solo chequea que exista la carpeta y que no esté `DISABLE_ENTERPRISE`; `lib/chatwoot_app.rb:14-18`). `CaptainListener` está registrado, pero Captain/SLA siguen detrás de feature flags por cuenta y del plan de la instalación.

---

## 1. Eventos: dispatcher y listeners

- `app/dispatchers/dispatcher.rb`: singleton. `dispatch(name, ts, data)` llama a `SyncDispatcher` y después a `AsyncDispatcher` (`:44-56`). Usa Wisper.
- `SyncDispatcher` (en proceso): `ActionCableListener`, `AgentBotListener` (`app/dispatchers/sync_dispatcher.rb:2-9`).
- `AsyncDispatcher` (encola `EventDispatcherJob`, cola `critical`): AutomationRule, Campaign, CsatSurvey, Hook, InstallationWebhook, Notification, Participation, UnreadCounts, ReportingEvent, Webhook (`app/dispatchers/async_dispatcher.rb:10-24`). Enterprise suma `CaptainListener` vía `prepend_mod_with` (`enterprise/app/dispatchers/enterprise/async_dispatcher.rb`).
- Registro: `config/initializers/event_handlers.rb` (`to_prepare` → `Dispatcher.instance.load_listeners`).
- Ruteo: `lib/events/base.rb:11-13`. El evento `message.updated` llama a `#message_updated(event)`. `event.data` es un Hash.
- `BaseListener` (`app/listeners/base_listener.rb`): singleton, con helpers `extract_conversation_and_account`, `extract_message_and_account`, `extract_changed_attributes`.
- Lista de eventos: `lib/events/types.rb:5-62`. Los relevantes:
  - `message.created`, `message.updated`, `first.reply.created`, `reply.created`
  - `conversation.created|updated|status_changed|resolved|opened|mentioned`
  - `assignee.changed`, `team.changed`, `contact.updated`
- En listeners async el modelo llega serializado por GlobalID (recargado de DB). `saved_change_to_*` no sirve ahí; usar `event.data[:previous_changes]` / `[:changed_attributes]`.

**Cómo registrar listeners Arroyo:** agregar `Arroyo::...Listener.instance` al array de `AsyncDispatcher#listeners` con `# ARROYO:`. Es una línea en un archivo core y queda compatible con el `super +` de enterprise. Deben ir en el dispatcher **async**: no hay que bloquear el request y el sync solo tiene ActionCable y bots.

### message.created
`after_create_commit` → `dispatch_create_events` (`app/models/message.rb:137, 324-333, 378-387`). Se dispara **siempre**: notas privadas, actividad, salientes de cualquier sender.

### message.updated — ¿se dispara al cambiar `status`? **Sí.**
- `after_update_commit :dispatch_update_event` (`message.rb:139, 389-395`). Solo exige `previous_changes.present?`. Data: `message:`, `performed_by:`, `previous_changes:`.
- El cambio de status de WhatsApp usa `save!` (ver §3), así que dispara el evento.
- Para saber si cambió el status: `event.data[:previous_changes]['status']`.

### Labels — **no hay evento específico**
- Labels con `acts_as_taggable_on :labels` (`app/models/concerns/labelable.rb:5`): tablas `taggings`/`tags` más `conversations.cached_label_list` (texto separado por comas).
- Al cambiar labels se dispara `conversation.updated` con `changed_attributes: previous_changes` (`app/models/conversation.rb:281-290, 320-323`). `label_list` está en la lista de claves que lo disparan.
- `changed_attributes['label_list'] == [old_array, new_array]`. Agregadas = `new - old`, sacadas = `old - new`. Es lo mismo que hace core en `create_label_change` (`conversation.rb:343-351`).
- Ojo: borrar una label a nivel cuenta (`Labels::DestroyService`, `update_column`) **no** dispara eventos.
- La fecha en que se aplicó una label está en `taggings.created_at`, útil para métricas históricas (ver §11).

### assignee.changed
`AssignmentHandler#notify_assignment_change` (`app/models/concerns/assignment_handler.rb:26, 49-56`) dispara `ASSIGNEE_CHANGED` con `changed_attributes` (incluye `assignee_id: [old, new]`). También se dispara al crear una conversación ya asignada.

---

## 2. Ventana de 24 hs

- `Conversation#can_reply?` → `Conversations::MessageWindowService#can_reply?` (`conversation.rb:129-130`, `app/services/conversations/message_window_service.rb`).
- Regla: `Time.current < last_incoming_message.created_at + ventana`. Sin ningún mensaje entrante → `false`.
- "Último entrante" = `conversation.messages.incoming.last` por `created_at` (`:67-69`). Los echoes (mensajes enviados desde la app de WhatsApp Business) se guardan como `outgoing` y no cuentan.
- Ventanas por canal:
  - WhatsApp (Cloud y 360dialog): 24 h fijas.
  - Facebook / Instagram: 24 h, o 7 días si está activo HUMAN_AGENT.
  - API: 48 h por defecto, o `agent_reply_time_window` del canal.
  - TikTok: 48 h.
- Uso en el frontend: `can_reply` viaja en el payload de conversación. Con la ventana cerrada, en WhatsApp el editor queda deshabilitado y solo deja mandar templates (`ReplyBox.vue:441-446`).
- **Bloqueo en backend (WhatsApp):** `Whatsapp::SendOnWhatsappService#perform_reply` fuerza el camino de template si `!conversation.can_reply?` (`app/services/whatsapp/send_on_whatsapp_service.rb:9`). Un texto libre con la ventana cerrada termina `status: failed`, `external_error: 'Template not found or invalid template name'`, **sin llegar a Meta**. La API igual devuelve 201.
- Facebook/Instagram no tienen chequeo en backend: el mensaje se manda y Meta lo rechaza (error guardado como `"code - message"`).

## 2b. HUMAN_AGENT (Instagram / Messenger) — **existe en 4.14.2**

- Configs de instalación: `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` (`config/installation_config.yml:145-150`) y `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` (`:431-436`). Default `false`.
- Se activan en **Super Admin → App Configs → Facebook / Instagram**. El ENV solo aplica si no existe la fila en DB, así que conviene usar Super Admin.
- Efecto: ventana de 7 días (`message_window_service.rb:63-65`). Los salientes van con `messaging_type: MESSAGE_TAG, tag: HUMAN_AGENT`:
  - Messenger: `app/services/facebook/send_on_facebook_service.rb:97-106`
  - Instagram directo: `app/services/instagram/send_on_instagram_service.rb:24-32`
  - Instagram vía página de Facebook: usa el flag de **Messenger** (`app/services/instagram/messenger/send_on_instagram_service.rb:31-38`)
- Requisito fuera del código: la app de Meta tiene que tener aprobado el permiso **Human Agent** (App Review). Sin eso Meta rechaza los mensajes con tag.

---

## 3. WhatsApp Cloud: status webhooks y errores

- Flujo: `Webhooks::WhatsappController` → `Webhooks::WhatsappEventsJob` → `Whatsapp::IncomingMessageWhatsappCloudService` → `process_statuses` (`app/services/whatsapp/incoming_message_base_service.rb:49-66`).
- Busca `Message.find_by(source_id: status[:id])`. `source_id` es el `wamid` guardado al enviar (`send_on_whatsapp_service.rb:37,42`).
- Setea `message.status = status[:status]`. Si es `failed`, también `message.external_error = "#{code}: #{title}"` y después hace `save!`, con lo que corren callbacks y se dispara `message.updated`.
- **`external_error` no es una columna**: es un accessor `store` dentro de `messages.content_attributes` (columna `json`, no `jsonb`; `message.rb:111-113`).
- Formatos de error:
  - Error asíncrono de Meta (webhook): `"131047: Re-engagement message"`. El código se parsea con `split(':', 2)`.
  - Error al enviar (respuesta HTTP de Meta): solo `error.message`, **sin código** (`whatsapp_cloud_service.rb:137-140`).
  - Error local: `'Template not found or invalid template name'`.
- Detalles:
  - Solo procesa `statuses.first` de cada webhook.
  - **No hay guarda contra regresión** (read → delivered) en este camino. La máquina de estados de follow-ups no debe retroceder.

## 4. Envío de templates de WhatsApp

- Mensaje saliente con `additional_attributes['template_params']` (`app/builders/messages/message_builder.rb:132-134,156`). El modelo lo valida con JSON schema (`message.rb:48-63`):
  ```ruby
  template_params: {
    name: 'postventa_d1',            # requerido
    category: 'MARKETING',
    language: 'es_AR',
    namespace: nil,                  # solo 360dialog
    processed_params: {
      body: { '1' => 'Juan', '2' => 'Mancuernas 10kg' },  # o nombrados si el template usa NAMED
      header: { media_url:, media_type:, media_name: },   # opcional
      buttons: [{ type: 'url', parameter: '...' }]        # opcional
    }
  }
  ```
- Pipeline: `after_create_commit` → `SendReplyJob` → `Whatsapp::SendOnWhatsappService` → `TemplateProcessorService` → `WhatsappCloudService#send_template`.
- El template se busca en `channel.message_templates` (jsonb, se sincroniza desde Meta cada ~3 h y al crear el canal) por `name` + `language` + `status == APPROVED`.
- Liquid también se aplica a `processed_params` (§9).
- Para verificar "template aprobado" antes de enviar: buscar en `inbox.channel.message_templates` con `name`, `language` y `status == 'APPROVED'`.

## 5. Mensajes interactivos (`input_select`) — **funciona**

- Ambos proveedores mandan `content_type: 'input_select'` (sin adjuntos) como interactivo (`app/services/whatsapp/providers/base_service.rb:57-105`):
  - Hasta 3 items: **botones** de respuesta (`reply.id = value`, `reply.title = title`).
  - Más de 3: **lista** con botón "Choose an item" (i18n backend).
- Forma: `content_attributes: { items: [{ title:, value: }] }` (validado en `app/models/concerns/content_attribute_validator.rb`).
- **No hay validación de largos** (Meta: título de botón ≤ 20 caracteres). Si se pasa, Meta lo rechaza y el mensaje queda `failed`. Validar en `Arroyo::Setting`: `nudge_buttons` con máximo 3 elementos de máximo 20 caracteres.
- Detalle a probar en staging: `action` se manda como string JSON (`JSON.generate`), no como objeto. Es el comportamiento nativo y se asume que Meta lo acepta.
- **Respuesta del cliente al botón:** entra como mensaje **entrante de texto plano** con el `title` del botón (`incoming_message_service_helpers.rb:27-34`). El `id`/`value` se pierde. Única señal: `content_attributes.in_reply_to_external_id` (wamid del nudge), que `Messages::InReplyToMessageBuilder` convierte en `content_attributes.in_reply_to` (id interno del nudge).

## 6. Qué dispara el envío al canal

- `SendReplyJob` se encola para **todo** mensaje creado (`message.rb:397-401`). El filtro está en `Base::SendOnChannelService#perform`:
  - envía si es `outgoing?` o `template?`
  - no envía si es privado, tiene `source_id`, o es `voice_call`
- **El sender no importa.** `conversation.messages.create!(message_type: :outgoing, sender: nil, ...)` sale por el pipeline normal y queda en el historial.
- Con sender `nil`:
  - `human_response?` es falso (`message.rb:362-371`): no cuenta como primera respuesta, no genera `reply_time` y no limpia `waiting_since`.
  - `bot_response?` también es falso.
  - Eso es lo que buscamos para nudges y follow-ups automáticos.

---

## 7. Scheduler

- `config/schedule.yml` (sidekiq-cron 2.4.0). Formato:
  ```yaml
  trigger_scheduled_items_job:
    cron: '*/5 * * * *'
    class: 'TriggerScheduledItemsJob'
    queue: scheduled_jobs
  ```
- Se carga en `config/initializers/sidekiq.rb:36-51` con `Sidekiq::Cron::Job.load_from_hash!(schedule, source: 'schedule')`. Las entradas que desaparecen del archivo se borran solas.
- `spec/configs/schedule_spec.rb` valida que no haya claves duplicadas.
- Plan: 3 entradas Arroyo con `# ARROYO:` (`arroyo_window_keeper_scan_job`, `arroyo_follow_ups_dispatch_job`, `arroyo_follow_ups_watchdog_job`), más una para campañas de email si se usa cron en vez de reprogramar jobs.

---

## 8. Email saliente

- `ConversationReplyMailerHelper#prepare_mail` (`app/mailers/conversation_reply_mailer_helper.rb:4-30`):
  1. `oauth_smtp_settings` (`:34-60`): **solo si `channel.imap_enabled`**.
     - Gmail: `smtp.gmail.com`. Microsoft: `smtp.office365.com`.
     - Puerto 587, `user_name: imap_login`, `password: provider_config['access_token']`, `authentication: 'xoauth2'`.
  2. `set_delivery_method` (`:62-80`): si `channel.smtp_enabled`, usa las columnas `smtp_*` del canal. Gana sobre OAuth si están ambos.
  3. Si no aplica ninguno, se usa el SMTP global de ENV (`config/initializers/mailer.rb`).
- **El mailer no refresca tokens OAuth.** Lee el `access_token` guardado. Solo el fetcher IMAP (cada 1 min) lo refresca con `Google::RefreshOauthTokenService` / `Microsoft::RefreshOauthTokenService` (`app/services/base_refresh_oauth_token_service.rb`).
- From / Reply-To para inboxes de email: `channel.email` cuando hay OAuth o SMTP propio (`helper:101-105`). Hay un camino nuevo detrás del feature flag `reply_mailer_migration` (`Email::FromBuilder`, `Email::ReplyToBuilder`).
- Entrada: `EmailChannelFinder` matchea To/Cc/X-Original-To contra `channel.email` o `forward_to_email`. Una respuesta a una campaña con Reply-To = `channel.email` y sin `In-Reply-To` conocido crea **una conversación nueva** en el inbox, que es lo que pide el plan.
- **Reutilización para `Arroyo::CampaignMailer`:** `include ConversationReplyMailerHelper`, setear `@inbox`, `@channel`, `@options`, y llamar `oauth_smtp_settings` + `set_delivery_method` antes de `mail(@options)`.
  - Antes de cada lote con OAuth: llamar `<Provider>::RefreshOauthTokenService.new(channel:).access_token`.
  - Los métodos del helper son privados del módulo pero se pueden usar al incluirlo. Es acoplamiento a un helper interno, así que hay que revisarlo en cada upgrade.
- Mailer global: `ApplicationMailer` con `default from: ENV['MAILER_SENDER_EMAIL']`. En dev, `letter_opener` si está seteado `LETTER_OPENER`.

## 9. Liquid en mensajes

- `Liquidable` (`app/models/concerns/liquidable.rb`) corre en `before_create` de **todo** mensaje `outgoing`/`template` con contenido, sin importar sender ni si es privado.
- Drops:
  - `contact`: name, first_name, last_name, email, phone_number, custom_attribute
  - `agent`: sender o asignado
  - `conversation`: display_id, custom_attribute
  - `inbox` y `account`: name
- Consecuencia: **NudgeService y SendService no tienen que renderizar Liquid**. Se guarda el texto con `{{contact.first_name}}` y Chatwoot lo resuelve.
- El mailer de campañas sí tiene que renderizar por su cuenta (`Liquid::Template.parse(...).render('contact' => ContactDrop.new(contact))`).

## 10. Segmentos guardados (custom filters)

- `CustomFilter` (`app/models/custom_filter.rb`): `filter_type` enum `conversation | contact | report`, `query` jsonb. Pertenece a un `user` (los filtros son por usuario).
- Forma de `query`: `{ "payload": [{ "attribute_key", "filter_operator", "values": [], "query_operator": "and"|"or"|null }] }`.
- Para resolverlo: `Contacts::FilterService.new(account, user, custom_filter.query.with_indifferent_access).perform[:contacts]`. Funciona desde un job (ya lo hace `Account::ContactsExportJob`). Una query inválida levanta `CustomExceptions::CustomFilter::*`.

## 11. reporting_events

- Columnas: `name, value (seg), value_in_business_hours, account_id, inbox_id, user_id, conversation_id, event_start_time, event_end_time, created_at`.
- Índices: `(account_id, name, created_at)`, `(account_id, name, inbox_id, created_at)`, más índices simples.
- Eventos (`app/listeners/reporting_event_listener.rb`):

| name | user_id | value |
|---|---|---|
| `first_response` | **sender del mensaje** (el que respondió) | último handoff/apertura → mensaje |
| `reply_time` | assignee | waiting_since → mensaje |
| `conversation_resolved` | assignee | creación → resolución |
| `conversation_opened`, `conversation_bot_handoff`, `conversation_bot_resolved` | assignee | — |
| `conversation_captain_inference_*` | assignee | — (solo EE) |

- **No hay evento de asignación.** Ver diferencias (D7).
- También existe `reporting_events_rollups` (agregados diarios).

## 12. Índices relevantes

- `messages`:
  - `(account_id, created_at, message_type)`: sirve para "salientes de la cuenta en un rango"
  - `(conversation_id, account_id, message_type, created_at)`
  - `(sender_type, sender_id)`
  - `source_id`
  - `(account_id, inbox_id)`
- `conversations`:
  - `(account_id, inbox_id, status, assignee_id)`
  - `(assignee_id, account_id)`
  - `(status, account_id)`
  - **no hay `(account_id, created_at)`**
- `messages.content_attributes` es `json`, no `jsonb`. Filtrar por `content_attributes->>'arroyo_kind'` funciona pero no se puede indexar con GIN. Para excluir mensajes automáticos en métricas conviene usar `sender_id IS NOT NULL AND sender_type = 'User'`, que de paso excluye bots.

## 13. Menciones y notificaciones

- Formato: `[@Nombre](mention://user/ID/Nombre%20URL-encoded)`. También existe `mention://team/ID/...`.
- `NotificationListener#message_created` → `Messages::MentionService` (solo para notas privadas con contenido).
- **El mencionado tiene que ser administrador o miembro del inbox**; si no, se descarta en silencio (`mention_service.rb:40-49`).
- Resultado: registro `Mention`, el usuario pasa a participante y se crea una notificación `conversation_mention`. Push y email salen según `notification_settings` de cada usuario. El email usa el SMTP global.
- Mencionar a Julieta y Marcos en la nota privada de alerta ya les manda **email nativo** si lo tienen activado en su perfil (ver D10).

## 14. Bot de n8n (relevado del workflow "bot-arroyo-v2", 2026-10-06)

**Cómo está conectado:** casi seguro es un **Agent Bot asignado al inbox**. Responde con la credencial "Chatwoot - bot" y solo actúa sobre conversaciones `pending`, que es el status que Chatwoot les da a las conversaciones de un inbox con bot activo (`conversation.rb:257-263`).

**Filtros de entrada** (en orden):
1. `incoming?`: `event == message_created`, `message_type == incoming`, `conversation.messages[0].message_type == 0`, `private != true`.
2. `Tiene contenido?`: texto o adjunto.
3. `Menos de 5 segundos?`: el mensaje tiene menos de 30 s (`messages[0].updated_at` contra ahora).
4. **`status pending`: `conversation.status == 'pending'`.** Si no, no hace nada.
5. Debounce de 8 s en Redis por conversación.

**Consecuencias para Arroyo:**
- Mensajes salientes de Arroyo (nudge, follow-up) y notas privadas de alerta: el bot los ignora por el filtro 1. No hace falta tocar n8n.
- **Respuesta del cliente a un nudge:** el nudge solo va a conversaciones `open` (`only_statuses`), así que el entrante cae en una conversación `open` y el filtro 4 la descarta. **No hace falta cambio en n8n.** Condición: `only_statuses` **no** puede incluir `pending`; validarlo en `Arroyo::Setting`.
- **Respuesta del cliente a un follow-up post-venta (riesgo):** para d7/d30 la conversación probablemente esté `resolved`. Un entrante en una conversación resuelta de un inbox con bot activo la pasa a **`pending`** (`message.rb:424-427`), y entonces **contesta el bot y no el vendedor**. Ver D19.
- Bot que se reactiva solo: si el bot maneja la conversación, el historial que arma ("Sintetizar contexto") va a incluir los nudges y follow-ups como mensajes `assistant`. Es correcto, no requiere cambios.
- **Interactivos confirmados en prod:** el bot ya manda `input_select` con 5 items (lista) en 4.14.2. El nudge usa el mismo código con ≤3 items (botones).
- Las respuestas del bot tienen `sender_type = 'AgentBot'`. Las métricas del panel que filtran `sender_type = 'User'` las excluyen solas.

**Payload que recibe** (para referencia, `message.rb:180-198`): `content_attributes` (incluye `arroyo_kind`), `message_type`, `private`, `sender` y `conversation` completo, con `status`, `additional_attributes`, `labels` y `messages[0]`.

## 15. Macros y automatizaciones

- Acciones de macro (`app/models/macro.rb:33-35`): `add_label`, `send_message`, `add_private_note`, `assign_agent`, `remove_label`, `change_status`, etc.
- Una macro "Registrar venta" puede poner la label `compra`. **No puede "pedir producto"**: las macros no tienen input del usuario. El producto se carga a mano como atributo personalizado de contacto/conversación.
- Los mensajes de automatizaciones llevan `content_attributes.automation_rule_id`.

## 16. Frontend

- Rutas:
  - Se agregan en `app/javascript/dashboard/routes/dashboard/dashboard.routes.js:20-34` (los `children` de `accounts/:accountId`). Patrón a copiar: `campaigns/campaigns.routes.js`.
  - Reportes: `routes/dashboard/settings/reports/reports.routes.js`, con `meta: { featureFlag: REPORTS, permissions: ['administrator','report_manage'] }`.
  - El router chequea `meta.permissions` (`helper/routeHelpers.js`) pero **no** `featureFlag`; ese solo lo usa el sidebar.
- Sidebar:
  - `components-next/sidebar/Sidebar.vue`: `menuItems` computado (`:280-790`); Reportes en `:535-567`; Configuración en `:637-788`.
  - Ítem: `{ name, label, icon: 'i-lucide-*', to: accountScopedRoute(...), activeOn, children }`.
  - La visibilidad sale de `meta` de la ruta destino. Para ítems condicionales hay un patrón de spread: `...(cond ? [item] : [])` (`:676-694`).
  - **Es un archivo core**: el ítem "Panel" y el ocultamiento de "Reportes" van con `// ARROYO:`.
- Configuración:
  - Nueva subpágina en `routes/dashboard/settings/<x>/<x>.routes.js`, agregada en `settings.routes.js`.
  - Ejemplo de formulario: `settings/security/components/SamlSettings.vue` (`SectionLayout`, `WithLabel`, `components-next` Input/Switch/Button).
- Gráficos: **chart.js 4 + vue-chartjs 5**, wrapper `app/javascript/shared/components/charts/BarChart.vue`.
- Componentes reutilizables:
  - Date picker: `components/ui/DatePicker/DatePicker.vue`
  - Multi-select: `components-next/filter/inputs/MultiSelect.vue`
  - Tabla: TanStack, con `components/table/Table.vue` (ejemplo: `reports/components/overview/AgentTable.vue`)
  - Tarjetas: `reports/components/overview/MetricCard.vue`
  - CSV: `helper/downloadHelper.js#downloadCsvFile`
  - Filtros en query params: `reports/helpers/reportFilterHelper.js`
- No hay componente drawer genérico. El panel lateral de drill-down se arma copiando el patrón de `routes/dashboard/conversation/contact/EditContact.vue:37-68` (panel fijo a la derecha, con transición y cierre con Esc).
- API client: `api/ApiClient.js` con `accountScoped: true` (ejemplo: `api/macros.js`). Store: conviven Vuex y Pinia; para páginas nuevas y aisladas alcanza con Pinia o estado local.
- Tokens para modo claro/oscuro: `bg-n-solid-2`, `bg-n-surface-1`, `text-n-slate-12`, `text-n-slate-11`, `border-n-weak`, `outline-n-container`.
- i18n:
  - `dashboard/i18n/locale/{en,es}/*.json`, mergeados planos en cada `index.js`. Agregar `arroyo.json` en **en y es** e importarlo en ambos `index.js` (`// ARROYO:`), con una clave raíz única `ARROYO`.
  - No hay `fallbackLocale`: una clave que falte en `es` se ve rota. Hay que mantener los dos archivos completos.
  - Backend: `config/locales/en.yml` / `es.yml` (o archivos `arroyo.en.yml` / `arroyo.es.yml` propios, que Rails carga solos).

---

## Diferencias contra el plan

| # | Plan | Realidad en 4.14.2 | Propuesta |
|---|---|---|---|
| D1 | Rebasar el fork sobre el tag de prod | El fork no tenía commits propios | Hecho: `arroyo/main` sale de `v4.14.2`. No usar `develop`. |
| D2 | Listener de labels | No hay evento de labels | `Arroyo::LabelsListener#conversation_updated`, diff de `changed_attributes['label_list']`. Borrar una label a nivel cuenta no dispara nada (aceptable). |
| D3 | "Listener de status o hook en el procesamiento de WhatsApp" | `message.updated` se dispara con el cambio de status (`save!`) | Listener `message_updated` filtrado por `previous_changes['status']` y mensajes con follow-up asociado. **No hace falta hook core.** |
| D4 | `external_error` como columna | Es un accessor dentro de `content_attributes` (json). Formato `"131047: Re-engagement message"` en webhooks; sin código en errores de envío; texto local `'Template not found…'` | Parsear con `/\A(\d+):\s*(.*)\z/`. Si no matchea → `error_code = nil` y alerta genérica con el texto. |
| D5 | NudgeService renderiza Liquid | Chatwoot ya renderiza Liquid en todo saliente (`before_create`) | Guardar el texto crudo; no implementar render propio (salvo en el mailer de campañas). |
| D6 | SendService elige texto libre o template según ventana | Core ya fuerza template si `!can_reply?` y marca `failed` sin llegar a Meta | Decidir con el mismo `conversation.can_reply?` (fuente única). En Instagram/Facebook no hay template: con la ventana cerrada → alerta directa. |
| D7 | "Conversaciones nuevas asignadas" desde reporting | No hay evento de asignación en `reporting_events` | Tabla propia `arroyo_assignment_events` llenada por un listener `assignee_changed`. **Solo hay datos desde el deploy**, sin histórico. Alternativa sin tabla: `conversations.created_at` por `assignee_id` actual (impreciso). |
| D8 | "Ventanas cerradas" / "Ventas registradas" por día y vendedor | La fecha de la label sale de `taggings.created_at`. El vendedor sería el **asignado actual**, no el del momento | Para `compra`: `arroyo_follow_ups.seller_id` (Fase 3). Para `ventana-cerrada`: guardar el asignado al aplicar la label (columna en una tabla de eventos Arroyo). Mientras tanto, histórico aproximado con taggings + asignado actual. |
| D9 | Excluir mensajes automáticos por `arroyo_kind` | `content_attributes` es `json` (no indexable con GIN) | Mensajes Arroyo con `sender: nil` → las métricas filtran `sender_type = 'User'`, lo que excluye también bots y automatizaciones de sistema. `arroyo_kind` queda igual para n8n y para la UI. |
| D10 | Alerta con mención + mail propio | La mención ya genera email nativo según la preferencia del usuario; además exige que el usuario sea admin o miembro del inbox | Mantener `alert_email` pero apagado por defecto si Julieta y Marcos tienen activo el mail de menciones (evita mails duplicados). Validar en Settings que los `alert_user_ids` sean admins o miembros de los inboxes WhatsApp. |
| D11 | Macro "Registrar venta" que pida producto | Las macros no piden input | Macro solo pone la label. El producto se carga en un atributo personalizado (`producto_comprado`) a mano, o en un futuro modal Arroyo. |
| D12 | Botones del nudge | Funcionan (≤3 botones; >3 → lista; el bot ya usa listas en prod). Sin validación de largo; la respuesta llega como texto plano + `in_reply_to` | Validar en Settings máx. 3 botones de máx. 20 caracteres. |
| D13 | Que la respuesta al botón no active al bot | El bot solo responde en conversaciones `pending`; el nudge va a `open` | **Resuelto sin tocar n8n.** Settings rechaza `pending` en `only_statuses`. |
| D14 | Registrar listeners "en el dispatcher" | Hay que editar `app/dispatchers/async_dispatcher.rb` | Una línea con `# ARROYO:` en el array `listeners`. |
| D15 | Email marketing reusa `ConversationReplyMailer` | OAuth solo si `imap_enabled` y sin refresh en el mailer | `Arroyo::CampaignMailer` incluye `ConversationReplyMailerHelper` y refresca el token antes de cada lote. Validar al elegir inbox que tenga SMTP propio u OAuth con IMAP activo; si no, el envío caería en el SMTP global con un From que no corresponde. |
| D16 | Textos es + en | El CLAUDE.md de upstream dice "solo en.json"; es/ lo pisa Crowdin en upstream | Archivos `arroyo.json` separados en en/ y es/ (Crowdin no los toca porque el fork no sincroniza). Regla anotada en CLAUDE.md. |
| D17 | Índices | Falta `conversations (account_id, created_at)` y `messages (account_id, sender_type, sender_id, created_at)` | Decidir en Fase 4 después de medir con el seed; migración `concurrently`. |
| D18 | Edición CE/EE en prod | Prod corre la imagen construida desde `arroyo/main`, con código EE activo | Nada que hacer. Captain sigue detrás de flags por cuenta. |
| D19 | Follow-up post-venta → responde el vendedor | Si la conversación está `resolved`, la respuesta del cliente la pasa a `pending` y **contesta el bot** | **Decidido:** si no está `open`, SendService la reabre como `open` con el vendedor asignado antes de mandar. En la práctica casi nunca hace falta, porque Arroyo no suele cerrar conversaciones. |

## Decisiones tomadas (2026-10-06)

- **Label de venta = `vendido`.** Arroyo identifica las ventas por esa label (casi no cierran conversaciones). `post_sale.trigger_label` arranca en `"vendido"`, y "Ventas registradas" del panel cuenta esa label. `PLAN.md` ya está actualizado.
- **Post-venta reabre la conversación** como `open` antes de mandar (D19).
- **El panel no tiene métrica "Resueltas".** Se sacó porque Arroyo casi no resuelve conversaciones.
- **Instagram queda fuera de los envíos automáticos.** Está conectado directo (`Channel::Instagram`) y la app de Meta no tiene Human Agent, así que la ventana es de 24 h y no hay templates.
  - Window keeper: solo WhatsApp (ya era así).
  - Post-venta: un follow-up de una conversación que no es de WhatsApp **no se envía**; va directo a alerta para seguimiento manual. Queda como mejora futura mandar por la conversación de WhatsApp del contacto si existe.
  - No activar `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT`.
- **Email marketing solo con SMTP propio del inbox** (`channel.smtp_enabled`). El selector de inbox muestra solo inboxes Email con SMTP propio. El mailer usa `set_delivery_method` del helper; no hace falta OAuth ni refresh de tokens (D15 simplificado).

### Pendientes que necesitan a una persona
1. ~~¿CE o EE?~~ Imagen propia desde `arroyo/main`, con EE activo (D18).
2. ~~¿Cómo está conectado el bot?~~ Agent Bot del inbox, solo responde en `pending` (§14).
3. ~~Instagram~~: directo, sin Human Agent; excluido de envíos automáticos.
4. ~~Inbox de email~~: SMTP propio.
5. ~~D19~~: reabrir y que conteste el vendedor.

Sin pendientes abiertos.

---

## Fase 4 — Panel de vendedores (implementado 2026-10-06)

- Endpoints (`config/routes/arroyo.rb`):
  - `GET arroyo/agent_panel` (reporte)
  - `GET arroyo/agent_panel/conversations` (drill-down)
  - `GET arroyo/agent_panel/windows` (pestaña Ventanas)
  - `GET arroyo/agent_panel/export` (CSV)
  - `GET arroyo/features` (flags para el menú, lo puede leer cualquier usuario de la cuenta)
- Con el panel apagado, todos los endpoints del panel devuelven 403. Un agente con `agents_see_only_own` solo ve lo suyo aunque pida otros `user_ids`.
- Métricas (`app/services/arroyo/agent_panel/`): una consulta por métrica con `GROUP BY GROUPING SETS`, que devuelve juntos los valores por vendedor y día/semana, el total por vendedor y el total general. Los días se agrupan con `AT TIME ZONE` de la zona del negocio.
  - "Consultas atendidas" y "Mensajes enviados": salientes no privados con `sender_type = 'User'` (D9).
  - "Conversaciones nuevas asignadas": tabla nueva `arroyo_assignment_events`, que llena `Arroyo::AssignmentListener` (registrado en `AsyncDispatcher`). **Hay datos desde el deploy, no antes.** El listener registra aunque el panel esté apagado, para que haya historia cuando se active.
  - "Mediana de primera respuesta": `reporting_events.first_response` (el `user_id` es quien respondió).
  - "Ventanas cerradas" y "Ventas registradas": `taggings.created_at` de las labels `ventana-cerrada` y `vendido` (o el `trigger_label` configurado), atribuidas al **asignado actual** (D8).
- Respecto del plan:
  - Sin "Resueltas" (decisión del cliente).
  - **"Alertas post-venta" y la pestaña "Post-venta" se agregan en la Fase 3**, porque dependen de `arroyo_follow_ups`.
  - El drill-down devuelve hasta 500 conversaciones (las de actividad más reciente) y el total.
- Performance (dev, 50k mensajes, 5k conversaciones, 8 vendedores):
  - Reporte de 7, 30 y 60 días: 14–19 ms.
  - Drill-down de 30 días de todos los vendedores: 132 ms.
  - Usa los índices existentes (`index_messages_on_sender_type_and_sender_id`, `(account_id, name, created_at)` de reporting_events). No hizo falta migración de índices.
- Frontend:
  - Ruta `/app/accounts/:id/arroyo/panel`. Los filtros viven en la URL (`preset`, `since`, `until`, `group_by`, `user_ids`, `inbox_ids`, `tab`).
  - "Panel de vendedores" aparece en el menú cuando el panel está activo. Si `hide_native_reports` está activo, se oculta "Reportes" del menú; la ruta nativa sigue funcionando.
- Archivos core tocados en esta fase: `app/dispatchers/async_dispatcher.rb`, `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (todos con `ARROYO:`).

## Alcance vigente — 16/10/2026

Por solicitud de Mauro se retiró el módulo Arroyo de respuestas a comentarios públicos. Se eliminaron sus pantallas, rutas, modelos, servicios, configuración y hooks; la mensajería nativa de Instagram/WhatsApp permanece intacta. No se continúa la adaptación a Instagram Login ni se configura un webhook de comentarios.

Se archivaron los tres workflows exclusivos de comentarios en n8n: `URLYZDOrdxjt5LnP`, `IQ5u9EC4W6s4fnAg` y `buLHjnIBKTRyy9zs`. Se conserva sin cambios la versión guardada y publicada de `fF0LK453uWJdBHsR` (seguimientos/postventa).

La migración histórica `20261014120000_create_arroyo_social_comments.rb` y sus tablas permanecen para respetar el historial y evitar pérdida de datos. No tienen rutas ni código de aplicación que las utilice. No se borran ni modifican migraciones existentes.

El alcance activo es panel de vendedores, seguimiento comercial y postventa D+1/D+7/D+30 con verificación de entrega y tareas manuales. Las plantillas y la conexión WhatsApp necesarias para postventa se conservan. La publicación del borrador de postventa y el despliegue de producción siguen siendo pasos separados.

## 20/10/2026 — Plantillas exclusivas

Por pedido del usuario, se reemplaza la selección texto libre/template de D6 por plantilla obligatoria para todas las etapas de postventa. El recordatorio de ventana mostrado en Ajustes era configuración sin job/servicio de envío implementado; se retira ese formulario, conservando el panel de ventanas. La configuración fija y el servidor no aceptan cuerpos alternativos de postventa. Ver docs/arroyo/n8n/TEMPLATE_ONLY.md para contratos y publicación gradual.

## 20/10/2026 — Límites del panel para el nuevo embudo comercial

El diseño en [SALES_FUNNEL_DESIGN.md](SALES_FUNNEL_DESIGN.md) parte de diferencias verificadas frente al recorrido comercial pedido:

- El reporte actual cuenta atendidas por fecha/autores de mensajes y asignadas por fecha/destinatarios de eventos; no mide una misma población de consultas. Sus diferencias no equivalen directamente a falta de atención.
- Las ventas del reporte usan tagging y asignado actual; la compra de postventa sí conserva un vendedor original. No usar la primera atribución como histórico comercial fiable.
- `Arroyo::AssignmentEvent` no registra explícitamente responsable anterior, actor ni origen. La alternancia Redis del subworkflow publicado `B5YmsSniVco8DT6Y` no incorpora tomas manuales.
- `PostSalePurchase` tiene unicidad por conversación; `RegisterPurchaseService` reutiliza ese registro. Recompras en el mismo chat requieren una migración nueva y cambios de contrato, no solo otra tarjeta.
- El clasificador comercial publicado compara actividad del chat para decidir inactividad al completar la secuencia. Eso no demuestra una respuesta del cliente.
- No hay emisor de recordatorios 23–24 h implementado en el código Arroyo ni en los workflows v3 revisados. Auditar automatizaciones nativas antes de atribuir un supuesto envío; no reinstalar el formulario retirado ni generar eventos ficticios.

Alternativa propuesta y aceptada a nivel conversacional: registro de oportunidades y eventos Arroyo, atención humana identificada por origen, venta atribuida al momento del resultado y reparto transaccional alimentado por asignaciones efectivas. El diseño escrito está pendiente de revisión; no se implementa ni publica como parte de esta documentación.
