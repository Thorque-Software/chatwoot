# Arroyo v3 — integración de n8n y Chatwoot

Fecha de relevamiento: 2026-10-13. Código local: rama `arroyo/dev`, commit `cd84f13eb64e919b906db5a07cffd8fdaca58d17`.

## Alcance y fuentes

Este documento reúne el contrato de integración verificado en el código de Chatwoot y las definiciones publicadas de los cuatro workflows de la carpeta Arroyo/v3, leídas con el plugin Arroyo. Las referencias locales son rutas relativas al repositorio con números de línea del commit relevado. No se ejecutaron envíos ni se modificó la operación de producción.

La documentación anterior del bot corresponde expresamente a `bot-arroyo-v2`, relevado el 2026-10-06 ([ARCHITECTURE_NOTES.md](ARCHITECTURE_NOTES.md), sección 14). Sus filtros y conclusiones sobre quién responde a un seguimiento son evidencia histórica de v2; este relevamiento describe la integración actual v3.

## Workflows publicados de Arroyo/v3

Inventario completo verificado en la interfaz de n8n: breadcrumb **Personal / Arroyo / v3**, **Total 4**, los cuatro con estado **Published**. Se verificó además la carpeta mediante el conector Arroyo. El detalle MCP devuelve `parentFolderId: null`; por eso la pertenencia se comprobó en la interfaz, no se dedujo de ese campo.

| Workflow | ID | Función |
|---|---|---|
| [arroyo v3](https://n8narroyo.thorque.com.ar/workflow/SAGFyESTLZLDdaNo) | SAGFyESTLZLDdaNo | Recibir consulta, saludar, preguntar localidad y derivar |
| [arroyo v3 · derivar a asesor](https://n8narroyo.thorque.com.ar/workflow/B5YmsSniVco8DT6Y) | B5YmsSniVco8DT6Y | Abrir, asignar y enviar presentación del asesor |
| [arroyo v3 · etiquetar conversacion](https://n8narroyo.thorque.com.ar/workflow/XAQWvjDpb53SjBpW) | XAQWvjDpb53SjBpW | Clasificar rubro preservando etiquetas ajenas |
| [arroyo v3 · seguimientos post-venta](https://n8narroyo.thorque.com.ar/workflow/fF0LK453uWJdBHsR) | fF0LK453uWJdBHsR | Postventa y secuencia de seguimiento comercial |

Se leyeron todos los nodos y conexiones, usando `activeVersion` como fuente de lo publicado. Los tres primeros coinciden con su versión guardada. Seguimientos tiene distintos IDs de versión publicada/guardada, pero la única diferencia encontrada es tamaño y posición de una nota: contenido, código y conexiones son iguales. No hay diferencia funcional observada.

Los cuatro tienen ejecuciones recientes con estado `success` el 13/10/2026. El cron de seguimientos registró una corrida a las **10:00 ART** (13:00 UTC), y las tres últimas corridas disponibles, 11/12/13 de octubre, figuran exitosas. Solo se leyeron metadatos de ejecución: no se consultaron conversaciones de clientes ni se disparó una prueba. `success` puede corresponder a filtros que no hacen nada o a errores continuados; no certifica entrega por Meta.

### 1. Recepción y localidad: arroyo v3

Fuente: nodos publicados del [workflow principal](https://n8narroyo.thorque.com.ar/workflow/SAGFyESTLZLDdaNo), especialmente `incoming?`, `status pending`, `Preparar Datos`, `Decidir Paso`, `Esperar Respuesta` y llamadas a subworkflows.

- Webhook POST `bot-arroyo`. Acepta `message_created`, entrantes no privados, con texto o adjunto, edad menor a 30 segundos y conversación `pending`.
- Debounce de 8 segundos: Redis guarda la ejecución más reciente por conversación, con TTL de 300 segundos. Solo esa ejecución sigue (también continúa si la clave desapareció).
- Usa textos fijos; no tiene nodos de IA, catálogo, stock ni precios. La nota del workflow atribuye la eliminación de venta al pedido del cliente del 30/09.
- Lee localidad de atributos personalizados del contacto cuyo nombre contiene `localidad`. Si ya existe, saluda y deriva directamente.
- Si falta, saluda y pregunta. Registra `v3:loc_pedida:<conversation_id>` durante 24 horas. El siguiente mensaje se interpreta con una heurística de localidad; si parece válido guarda `custom_attributes.localidad`; deriva aunque no pueda reconocer la localidad.
- Si no responde, espera 30 minutos, consulta otra vez el estado y deriva si continúa `pending` o no pudo obtener estado.
- Clasifica rubro en una rama separada que llama al subworkflow de etiquetas. El nodo está después del gate `pending`: no debe interpretarse como clasificación de todos los mensajes humanos en conversaciones `open`.
- Horario del local: lunes a sábado, **08:30–12:00 y 16:30–20:30**, en America/Argentina/Buenos_Aires. Se recalcula al despertar del timeout.
- Apunta a Chatwoot de producción y cuenta **1**. No consulta `Arroyo::Setting`.

### 2. Transferencia: derivar a asesor

Fuente: [workflow de derivación](https://n8narroyo.thorque.com.ar/workflow/B5YmsSniVco8DT6Y), nodos `Tomar Candado`, `StatusOpen1`, `agents1`, `Asignar agente1`, `juli`, `marcos` y `Nota Error Derivacion`.

Abre la conversación como `open`, asigna por turno a **Julieta (ID 4)** o **Marcos (ID 5)** y envía la presentación correspondiente. Fuera de horario primero avisa que deriva al sector especializado y luego informa que el asesor retomará la consulta cuando esté en el local.

Redis evita duplicados cercanos con `INCR v2:derivado:<conversation_id>`, TTL **120 segundos**. La primera ejecución continúa; el resto se detiene. Si Redis falla, el diseño permite continuar. Este subworkflow conserva claves heredadas de v2 aunque se llame desde v3.

El turno global se guarda en `rr:counter`. La operación de selección es lectura → cálculo → escritura; el candado es por conversación. Por tanto, la alternancia estricta entre conversaciones concurrentes no está garantizada por un contador global atómico. Es una deducción de los nodos, no un incidente observado.

Errores de asignación o de presentación van a una **nota privada** para intervención manual. No hay una notificación externa adicional en ese camino.

### 3. Rubro: etiquetar conversacion

Fuente: [workflow de etiquetado](https://n8narroyo.thorque.com.ar/workflow/XAQWvjDpb53SjBpW), `Decidir Etiqueta` y `Escribir Etiquetas`.

Administra únicamente `bici` y `aparatosgim`; conserva otras etiquetas como `vendido`, `seguimiento` o `cotizado`. Decide por prioridad: menú exacto heredado, campaña por parámetro, texto de campaña en primer mensaje y rubro mencionado si aún no hay etiqueta de rubro. V3 no ofrece menú y pasa `campana` vacía, así que sus rutas relevantes son las dos últimas.

Bicicleta fija y spinning son `aparatosgim`. Texto ambiguo de los dos rubros no decide. Si no hay cambio, no escribe. Envía el conjunto completo de etiquetas, con hasta dos intentos.

La clasificación es relevante para postventa: `aparatosgim` elige plantilla de gimnasio; sin esa etiqueta la postventa asume bicicleta. No equivale a identificar el producto vendido. El subworkflow es compartido con v2 y se invoca por ID, aunque algunos nombres cacheados todavía mencionen v2.

### 4. Un cron, dos ramas independientes

Fuente: [workflow de seguimientos](https://n8narroyo.thorque.com.ar/workflow/fF0LK453uWJdBHsR), `Diario 10hs ART`, `Config Chatwoot`, clasificadores y nodos HTTP de ambas ramas.

Corre diariamente a las **10:00 ART** y consulta conversaciones mediante la API de Chatwoot, con paginación de hasta **40 páginas de 25**. El parámetro `solo_conversaciones` está vacío en la versión publicada: no hay restricción a IDs de prueba. Ninguna rama consulta los flags del fork ni filtra canal/inbox en los payloads de búsqueda relevados.

#### 4a. Postventa por vendido

Busca `vendido` sin `seguimiento-listo`. Calcula días desde **la creación de la conversación**, no desde la aplicación de `vendido` ni desde una compra registrada.

| Etapa | Condición publicada | Plantilla |
|---|---|---|
| Recompra bicicleta | D+1 hasta D+7, todos los clientes elegibles | `arroyo_recompra_accesorios`, MARKETING |
| Recompra gimnasio | D+1 hasta D+7, etiqueta aparatosgim | `arroyo_recompra_accesorios_gym`, MARKETING |
| Service bicicleta | D+30 hasta D+75, zona local | `arroyo_recordatorio_service`, UTILITY |
| Seguimiento gimnasio D+30 | Zona local; plantilla vacía, queda en pausa dentro de plazo | `template_service_gym` sin configurar |

Zona local: prefijos telefónicos **3402/341** o etiqueta manual `zona-local`. No usa el atributo `localidad` capturado por el bot. Firma con el nombre del **asignado actual**, o `el equipo` si no hay asignado.

Máximo **40 acciones** por corrida, incluyendo vencimientos/cierres sin envío. Recompra vence después de D+7; service después de D+75. Los vencimientos usan las mismas marcas que el envío: `recompra-enviada` y `service-enviado` no prueban que haya salido un mensaje. Cuando no queda trabajo agrega `seguimiento-listo`; ese “cierre” es de la secuencia, **no cambia el status de conversación a resolved**.

El salto de domingo solo está conectado a la rama diaria: **la postventa también corre domingos**. Procesa una acción por conversación por corrida; recompra tiene prioridad sobre service.

`Enviar Plantilla WhatsApp` continúa por salida regular tras error, y el siguiente nodo escribe las marcas sin comprobar ID o entrega. Por lo tanto puede marcarse como procesado un intento que no creó o no entregó el mensaje.

#### 4b. Seguimiento comercial por seguimiento

Busca la etiqueta `seguimiento`, de lunes a sábado. Solo envía si el asignado coincide con alias de Juli/Julieta o Marcos. Producto de plantilla: `una bicicleta`, `equipamiento de gimnasio` o texto genérico según etiquetas.

La secuencia usa **seg_dia_1 → seg_dia_3 → seg_dia_5** según número de envío. Puede enviar en días hábiles consecutivos; no hay espera explícita de dos días entre pasos. Máximo **150 acciones** por corrida, hasta **tres envíos** por secuencia. Ordena primero por la fecha del último envío más vieja para rotar la cola.

Guarda en atributos **de conversación**:

- `seguimiento_ultimo_envio`: fecha local YYYY-MM-DD.
- `seguimiento_ultimo_envio_ts`: timestamp Unix del intento.
- `seguimiento_envios`: contador de pasos.

No vuelve a enviar si la marca es de hoy. Después del último paso espera **dos días** y retira `seguimiento`; agrega `inactivo` si no detecta actividad posterior al último envío más **10 minutos**. Esa señal es `last_activity_at`: puede ser actividad del cliente o del vendedor, no prueba específica de respuesta entrante. El contador vuelve a cero al terminar.

Conversaciones sin actividad por más de **45 días** se saltean; por más de **60 días** se retira la secuencia, agregando `inactivo` solo si hubo envíos previos registrados.

Solo marca un envío si la API devolvió un `id`. Esto confirma creación local, no entrega. No conserva ese ID para seguimiento ni consulta `delivered/read`. Si falla al guardar las marcas después de crear el mensaje, puede repetir el paso en una corrida posterior.

Los nodos `Marcar Envio Del Dia` y `Resetear Contador` envían únicamente esas tres claves. El endpoint local **reemplaza todo el hash**, así que pueden eliminar atributos personalizados ajenos. La preservación de atributos es distinta entre conversación y contacto; el bot sí conserva atributos de contacto al escribir localidad.

### Hallazgos que afectan las próximas fases

1. **Postventa existe en producción externa.** Fase 3 debe definir convivencia o migración antes de activar otro emisor para `vendido`. El cron externo funciona aunque los flags Rails estén apagados.
2. **El plan y la cadencia real difieren.** Plan: D1/D7/D30 desde compra/etiqueta y vendedor original. N8n: D1/D30 desde creación de conversación y asignado actual, segmentación por rubro/zona y seguimiento comercial separado.
3. **No hay confirmación de entrega.** Postventa marca tras intento; diario verifica creación local. Falta correlación `message_id`, status real, errores posteriores, watchdog y resolución manual.
4. **Siempre se solicita plantilla.** Ambas ramas incluyen `template_params`. El servicio core usa plantilla incluso con ventana abierta; `content` no hace selección automática de texto libre pese lo sugerido por algunas notas del workflow.
5. **La escritura de atributos diarios reemplaza claves ajenas.** Debe tenerse en cuenta antes de agregar estado nuevo sobre conversaciones.
6. **Las dos ramas pueden coincidir.** No hay exclusión de `vendido` en el filtro diario ni de `seguimiento` en postventa, ni exclusión por `no-contactar` en los clasificadores revisados. Una conversación puede resultar elegible para ambas; no se observó un caso real.
7. **No hay reapertura/asignación previa en estos envíos.** Si una conversación está resuelta, la respuesta del cliente puede volver a `pending` y entrar al bot de localidad/derivación. La decisión D19 del plan sigue siendo relevante.
8. **Emisor y métricas requieren verificación.** Los payloads n8n no fijan `sender_type`, `sender_id` ni `arroyo_kind`. El sender depende de la identidad de la credencial. El conector no expuso secretos ni permitió confirmar identidad/tipo real: no se concluye que todos los automatismos estén excluidos del panel.
9. **Ventanas no se mantienen con la postventa.** No se encontró en estos cuatro workflows un scan de último entrante a 22 horas ni etiquetas `ventana-cerrada`. Fase 2 agrega una responsabilidad nueva, pero debe coordinarse con seguimiento diario.
10. **El alcance v3 conserva atención humana.** No reintroducir IA de ventas, catálogo o recomendaciones automáticas en el bot como parte incidental de estas fases.

Propuesta para revisar antes de desarrollar: mantener los envíos actuales en n8n mientras se prepara la capa Rails; acordar por proceso el responsable único, la fecha de compra, cadencias y plantillas; preservar marcas existentes; incorporar entrega/alertas; y recién entonces realizar un corte controlado. No se modificó `PLAN.md` ni se implementó ese traspaso.

## Responsabilidades de Chatwoot

Chatwoot guarda contactos, conversaciones, mensajes, etiquetas, asignaciones y atributos personalizados. Expone una API para que n8n pueda realizar las mismas acciones operativas y publica eventos para activar procesos externos. El código local Arroyo agrega configuración por cuenta y panel comercial; la automatización externa no está contenida en el repositorio.

### Eventos hacia n8n

Hay dos mecanismos distintos, que conviene identificar en cada webhook de v3:

- **Agent Bot:** `AgentBotListener` publica `message_created`, `message_updated`, `conversation_updated`, `conversation_status_changed`, `conversation_opened` y `conversation_resolved`. El destino es `AgentBot.outgoing_url`, mediante `AgentBots::WebhookJob`. Fuentes: [agent_bot_listener.rb](../../app/listeners/agent_bot_listener.rb), líneas 2–51 y 65–89.
- **Webhook de cuenta:** `WebhookListener` publica eventos según las suscripciones del webhook configurado. También existe un webhook propio para inboxes de tipo API. Fuentes: [webhook_listener.rb](../../app/listeners/webhook_listener.rb), líneas 2–43 y 110–130.

El listener de Agent Bot **no filtra por estado `pending`**: reúne el bot asignado a la conversación y el bot activo del inbox y elimina duplicados. Por ello, la decisión de actuar sobre `pending`, `open` o determinadas etiquetas pertenece al workflow. El hecho de recibir un webhook no implica que el bot deba contestar. Fuente: `app/listeners/agent_bot_listener.rb`, líneas 65–89.

Los mensajes webhookeables son `incoming`, `outgoing` y `template`; el helper no excluye las notas privadas. n8n debe aplicar sus propios filtros de tipo y privacidad. Fuente: [message_filter_helpers.rb](../../app/models/concerns/message_filter_helpers.rb), líneas 8–10.

### Forma del payload y correlación de mensajes

`Message#webhook_data` incluye `id`, `source_id`, `message_type` como nombre, `private`, `content_attributes`, `additional_attributes`, `sender`, `conversation` y adjuntos. **No incluye `status` como campo superior**. Fuente: [message.rb](../../app/models/message.rb), líneas 180–198.

La conversación incluida contiene `id = display_id`, inbox, estado, etiquetas, atributos personalizados, metadatos del contacto/asignado y `messages`. Ese array contiene únicamente **el último mensaje de chat no privado**, no todo el historial. El mensaje anidado sí parte de todos los atributos del modelo y usa `message_type` numérico. Fuentes: [event_data_presenter.rb](../../app/presenters/conversations/event_data_presenter.rb), líneas 3–48; `app/models/message.rb`, líneas 146–156 y 173–177; scope `chat`, línea 118.

Consecuencia para verificar entregas: en `message_updated` el `id` superior identifica el mensaje actualizado, pero `conversation.messages[0]` podría ser un mensaje posterior. Un consumidor externo debe correlacionar ambos IDs antes de usar el status anidado, o consultar el mensaje correcto. Esta es una deducción del contrato, no un fallo observado en v3. Los listeners Rails reciben además `previous_changes`, que el webhook de mensajes no expone. Fuente: `app/models/message.rb`, líneas 246–248.

Las rutas de conversaciones buscan por `display_id` dentro de la cuenta, mientras relaciones y tablas internas utilizan el ID de base de datos. No conviene intercambiarlos en almacenamiento externo. Fuente: [conversations_controller.rb](../../app/controllers/api/v1/accounts/conversations_controller.rb), líneas 190–192; presenter, línea 8.

### Estados y transferencia al vendedor

| Acción | Comportamiento del código core | Fuente |
|---|---|---|
| Crear conversación en inbox con bot activo | Inicia en `pending`, excepto ramas específicas de bloqueo/campaña | `app/models/conversation.rb:257–268` |
| Bot solicita pasar `pending` a `open` por API | Ejecuta `bot_handoff!`: asegura `waiting_since`, abre y genera evento de handoff | `app/controllers/api/v1/accounts/conversations_controller.rb:81–98`; `app/models/conversation.rb:163–166` |
| Entrante en conversación `snoozed` | La abre si no está silenciada | `app/models/message.rb:403–409` |
| Entrante en conversación `resolved` con bot activo | La pasa a `pending` | `app/models/message.rb:424–433` |
| Entrante en conversación `resolved` sin bot | La pasa a `open` | `app/models/message.rb:424–433` |
| Respuesta saliente de bot n8n en `pending` | El método core que abre por respuesta humana devuelve false por defecto; no constituye por sí misma un handoff | `app/models/message.rb:412–421` |

Además, la recepción de WhatsApp reutiliza la última conversación si `lock_to_single_conversation` está activo; si no, busca una conversación no resuelta o crea una nueva. Esto determina si los atributos de estado del bot se conservan en el siguiente contacto. Fuente: [incoming_message_base_service.rb](../../app/services/whatsapp/incoming_message_base_service.rb), líneas 115–125.

La asignación a humano limpia el bot asignado a esa conversación, pero el bot de inbox sigue siendo un destinatario de eventos si está activo. La asignación a un bot limpia el humano. Fuente: [assignment_service.rb](../../app/services/conversations/assignment_service.rb), líneas 16–28, y `app/listeners/agent_bot_listener.rb:65–76`. No se debe equiparar asignación humana a suspensión de todos los webhooks.

### Persistencia de atributos y etiquetas

| Operación API | Semántica verificada | Implicación para procesos concurrentes |
|---|---|---|
| Atributos personalizados de conversación | Asigna el hash completo recibido | Preservar claves existentes antes de escribir; varios workflows pueden sobrescribirse |
| Actualizar atributos personalizados de contacto | Fusiona claves con las existentes | No tiene la misma semántica que la conversación |
| Etiquetas de conversación | `update_labels` reemplaza `label_list` con la lista recibida | Conservar etiquetas ajenas al workflow al agregar/quitar una |

Fuentes: `app/controllers/api/v1/accounts/conversations_controller.rb:136–138`; [contacts_controller.rb](../../app/controllers/api/v1/accounts/contacts_controller.rb), líneas 174–191; [label_concern.rb](../../app/controllers/concerns/label_concern.rb), líneas 2–4; [labelable.rb](../../app/models/concerns/labelable.rb), líneas 8–17. El riesgo de sobrescritura es una deducción de estas operaciones, no un incidente confirmado.

Cambios en `custom_attributes`, `label_list`, asignado y estado generan `conversation_updated`. Los cambios arbitrarios de `additional_attributes` no siempre lo hacen: la rama explícita contempla `conversation_language`. Fuente: `app/models/conversation.rb:280–296`. Un futuro diseño no debe trasladar señales desde custom a additional suponiendo que generan exactamente los mismos eventos.

## Pipeline de envío y entrega de WhatsApp

1. El endpoint de mensajes usa `Messages::MessageBuilder` y persiste el mensaje. El emisor saliente se toma del usuario/recurso autenticado, salvo `sender_type: AgentBot` explícito válido. `template_params` se guardan en `additional_attributes`. Fuentes: [messages_controller.rb](../../app/controllers/api/v1/accounts/conversations/messages_controller.rb), líneas 8–13; [message_builder.rb](../../app/builders/messages/message_builder.rb), líneas 116–156.
2. Después del commit se despacha `message_created` y se encola `SendReplyJob`. El job elige el servicio del canal; WhatsApp usa `Whatsapp::SendOnWhatsappService`. Fuentes: `app/models/message.rb:324–331, 378–400`; [send_reply_job.rb](../../app/jobs/send_reply_job.rb), líneas 4–27.
3. El servicio base solo entrega mensajes salientes o template, y excluye notas privadas o mensajes con `source_id` existente para evitar ecos. Fuente: [send_on_channel_service.rb](../../app/services/base/send_on_channel_service.rb), líneas 13–18 y 35–50.
4. WhatsApp utiliza template si recibe `template_params` o si `can_reply?` es false. Si no recibe nombre utilizable marca `failed` con error local. Si el proveedor devuelve un ID, lo guarda como `source_id`. Fuentes: [send_on_whatsapp_service.rb](../../app/services/whatsapp/send_on_whatsapp_service.rb), líneas 8–46; [template_processor_service.rb](../../app/services/whatsapp/template_processor_service.rb), líneas 4–37.
5. Cloud API publica el template y procesa la respuesta. Errores inmediatos se guardan como texto en `external_error` y estado `failed`; el código del proveedor no necesariamente está incluido en ese texto. Fuentes: [whatsapp_cloud_service.rb](../../app/services/whatsapp/providers/whatsapp_cloud_service.rb), líneas 14–31 y 137–139; [base_service.rb](../../app/services/whatsapp/providers/base_service.rb), líneas 34–54.
6. Webhooks de estados de WhatsApp encuentran el mensaje por `source_id`, guardan `sent`, `delivered`, `read` o `failed`; en failed con error guardan `"código: título"`. Ese `save!` dispara el evento de actualización. Fuentes: `app/services/whatsapp/incoming_message_base_service.rb:49–65`; `app/models/message.rb:103, 109–113, 389–394`.

`sent` es también el valor predeterminado del modelo al crear un mensaje; obtener HTTP exitoso al crear el mensaje y ver `sent` no demuestra entrega al cliente. Fuente: esquema de `app/models/message.rb:16` y secuencia de envío anterior.

La ventana de WhatsApp se calcula desde **el último entrante + 24 horas**. Enviar un mensaje o cambiar el status de la conversación no cambia ese cálculo. Fuente: [message_window_service.rb](../../app/services/conversations/message_window_service.rb), líneas 27–38 y 67–68. El estado operativo `open` y la ventana de envío abierta son conceptos independientes.

Los interactivos usan `input_select`: hasta tres items se convierten en botones y más de tres en lista. Fuentes: `app/services/whatsapp/providers/whatsapp_cloud_service.rb:2–10`; `app/services/whatsapp/providers/base_service.rb:85–90`.

Para métricas importa la credencial: el panel filtra `sender_type = 'User'`, mensaje saliente y no privado. Un workflow que use token de usuario puede aparecer como actividad humana; con AgentBot queda fuera. No se afirma aquí qué credencial usa cada workflow v3. Fuente: [scopes.rb](../../app/services/arroyo/agent_panel/scopes.rb), líneas 4–9.

## Estado del plan en el repositorio

| Fase | Evidencia local | Relación con v3 a revisar |
|---|---|---|
| 0 — Relevamiento | `ARCHITECTURE_NOTES.md` existe y describe v2 en §14 | Este documento y la actualización del 13/10 registran v3; D19 sigue relevante porque los envíos actuales no reabren antes de mandar |
| 1 — Base común | `Arroyo::Setting`, endpoints y UI de configuración | Sus flags regulan código local; los cuatro workflows revisados no los consultan |
| 2 — Window Keeper | Defaults/formulario disponibles; no hay jobs/listeners/servicios de nudge en namespace Arroyo | V3 no tiene scan de ventana a 22 horas; coordinarlo con el seguimiento comercial existente |
| 3 — Postventa | Defaults/formulario disponibles; no hay `arroyo_follow_ups` ni dispatch/watchdog/alerts en código local | N8n ya implementa D1/D30 por rubro y zona: acordar cadencia/fecha base y corte antes de activar Rails |
| 4 — Panel | Rutas/reportes/drill-down/CSV/ventanas y eventos propios de asignación implementados | Revisar credenciales de envíos automáticos y atribución comercial para no contar automatizaciones como vendedor |
| 5 — Email marketing | Defaults/formulario disponibles; no hay modelos/jobs de campañas Arroyo | Ninguno de los cuatro workflows v3 revisados implementa campañas de email |

Fuentes positivas: [setting.rb](../../app/models/arroyo/setting.rb), líneas 23–63; [config/routes/arroyo.rb](../../config/routes/arroyo.rb), líneas 3–10; [Index.vue](../../app/javascript/dashboard/routes/dashboard/arroyo/settings/Index.vue), líneas 72–90; `docs/arroyo/ARCHITECTURE_NOTES.md`, sección Fase 4. Ausencia de implementaciones: inventario de `app/models/arroyo`, `app/services/arroyo`, `app/listeners/arroyo`, `app/controllers/api/v1/accounts/arroyo`, migraciones y scheduler del commit relevado; no existe `app/jobs/arroyo`.

El panel registra toda nueva asignación humana en `Arroyo::AssignmentEvent`, aun con el panel apagado, y usa la hora del evento; no reconstruye histórico anterior. Fuente: [assignment_listener.rb](../../app/listeners/arroyo/assignment_listener.rb), líneas 2–14. Ventas y ventanas etiquetadas se atribuyen al asignado actual y la fecha del tagging, no al vendedor histórico. Fuente: `app/services/arroyo/agent_panel/scopes.rb:23–30`.

La pestaña Ventanas calcula último entrante + 24 horas, muestra las próximas seis horas y las cerradas hoy, y excluye conversaciones resueltas. No envía recordatorios. Fuente: [windows_finder.rb](../../app/services/arroyo/agent_panel/windows_finder.rb), líneas 4–15 y 21–39.

## Decisiones necesarias antes de las próximas etapas

1. **Responsable único de cada automatización:** determinar qué seguirá ejecutando n8n y qué se migrará a Rails; evitar dos programadores activos para el mismo seguimiento.
2. **Contrato de estado del bot:** documentar cada clave de `custom_attributes`, su propietario, transiciones, expiración y comportamiento en `open`, `pending` y nueva conversación.
3. **Postventa existente frente a Fase 3:** comparar disparador, etapas, horarios, cancelaciones, idempotencia, entrega y resolución manual. No asumir que sus etapas coinciden con d1/d7/d30 del plan.
4. **Respuesta al seguimiento:** verificar si v3 abre/asigna antes de enviar y cómo enruta una respuesta; revalidar D19 con los estados actuales.
5. **Correlación de entrega:** definir cómo relacionar operación externa, mensaje Chatwoot y `source_id` de Meta; el status anidado del webhook solo es utilizable si corresponde al mensaje superior.
6. **Etiquetas y escritura concurrente:** conservar las listas y atributos del bot/postventa/panel al agregar señales nuevas; acordar claves con namespace Arroyo para extensiones.
7. **Actividad humana y comercial:** confirmar el tipo de sender de cada automatización y si la label efectiva de venta coincide con `post_sale.trigger_label` (`vendido` por defecto).
8. **Flags y corte de migración:** no activar una etapa local creyendo que apaga su equivalente externo; primero verificar consumo de settings por n8n y planear el traspaso de pendientes.

Estas son decisiones propuestas para la próxima etapa a partir del contrato local y los workflows publicados relevados; no implican que se haya implementado un reemplazo o alterado producción.
