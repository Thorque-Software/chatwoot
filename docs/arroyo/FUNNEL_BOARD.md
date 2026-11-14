# Embudo del panel (funnel_board)

Pedido del equipo de marketing de Arroyo (13/11/2026): ver en una sola pantalla el recorrido completo de las consultas, por vendedor, por día y por anuncio, con las abandonadas y la recompra. Facturación queda afuera. Rama `feat/arroyo-embudo`.

Todo vive en **una sola sección de configuración** (Ajustes → Arroyo → *Embudo del panel*) y **una sola pestaña** del panel (Actividad). Viene **apagado**; con el interruptor apagado el panel sigue mostrando el embudo anterior (`FunnelTab`) sin cambios.

## Qué muestra

| Bloque | Contenido |
| --- | --- |
| Números clave | Consultas (por anuncio / orgánicas), en bot o sin asignar, sin atender, atendidas (% de las derivadas), ganadas (% de las consultas), perdidas, abandonadas (avisos de ventana enviados). Aviso cuando hay consultas trabadas. |
| Recorrido | Gráfico de izquierda a derecha: origen (campaña o anuncio de Meta, u orgánica) → a quién le toca (vendedor, bot, sin asignar) → en qué quedó (sin atender, en curso, cliente dejó de responder, abandonada, perdida, ganada). Los estados que traban (sin atender, abandonada) se remarcan. Cada bloque abre sus conversaciones. |
| Etiquetas informativas | `cotizado`, `cuota`, `turnotaller` (configurables, cada una con interruptor). Solo referencia. |
| Por vendedor | Recibidas, atendidas, sin atender, en curso, inactivas, abandonadas, perdidas, ganadas y % ganadas. |
| Por día | Tabla día × vendedor con el dato elegido. Cada celda abre las conversaciones. Exportable a CSV. |
| Ventas por anuncio | Campañas con sus anuncios: consultas, atendidas, ganadas, perdidas y % ganadas. Orgánica al final. |
| Recompras / Postventa que no salió | Clientes que volvieron a comprar, respuestas a la postventa y los mensajes de postventa fallidos, no ejecutados o sin confirmar, con el motivo. |

Filtros: fecha (día o rango), vendedor y número de WhatsApp (los números configurados, con su nombre).

## Criterios

- **Cohorte**: consultas por fecha de llegada (`started_at`) en la zona horaria del negocio. El embudo registra consultas desde el 21/10/2026.
- **Vendedor**: toda la métrica va al vendedor **actual**. Si Marcos toma una consulta de Juli, cuenta entera para Marcos (recibida, atendida y resultado). Por eso los números de días anteriores pueden cambiar después de una reasignación.
- **Atendida**: el vendedor mandó al menos un mensaje (`first_human_at`). Mensajes automáticos (bot, seguimientos, aviso de ventana) no cuentan.
- **Ganada**: etiqueta `vendido` (estado `won`, ya unificados). **Perdida**: etiqueta configurada (`noquierenada` por defecto) o la histórica `venta-perdida`.
- **Abandonada**: se mandó el aviso de ventana y pasaron *horas para considerar abandonada* (24 corridas por defecto) sin mensaje del vendedor, y la conversación no tiene las etiquetas excluidas (`seguimiento`). Se calcula al leer: si el vendedor vuelve a escribir o le ponen seguimiento, deja de estarlo. No se guarda ni se informa a n8n (el `state` de `contexts` no cambia).
- **Origen**: el anuncio de Meta que abrió la consulta (`arroyo_opportunities.origin`). Sale del `referral` de Meta, no del texto: no se pierde si el cliente borra el mensaje precargado. Sin anuncio = **orgánica**. Una recompra posterior en la misma conversación no hereda el anuncio viejo (`ad_referral_at`).
- **Recompra**: al ganar una consulta de un cliente que ya tenía otra venta (consulta ganada o compra de postventa) se le pone la etiqueta `recompra` (configurable).
- **Permisos**: todos los usuarios de la cuenta ven los números de todos. El detalle (lista de conversaciones) respeta los permisos de siempre: con *los vendedores solo ven su propia actividad*, un vendedor solo abre sus conversaciones.

## Aviso antes de que cierre la ventana

Apagado por defecto (`funnel_board.window_nudge.enabled`). Un job cada 15 minutos (`Arroyo::Commercial::WindowNudgeJob`) busca ventanas abiertas donde **el vendedor escribió último y el cliente no contestó**, y manda **un solo** mensaje de texto libre (la ventana sigue abierta, no usa plantilla):

- Si la ventana dura hasta la **mañana del día en que cierra**, sale a la hora de la mañana (08:30 por defecto).
- Si cierra antes, sale el **día anterior a más tardar a la tarde** (19:00 por defecto).
- Nunca los domingos (configurable), nunca antes de una hora después del último mensaje del vendedor y siempre con margen antes del cierre (30 min). Si no queda un horario válido, no se manda.
- No se manda a conversaciones con etiquetas excluidas (`seguimiento` por defecto), vendidas, perdidas, `no-contactar` o `venta-cancelada`, ni a bandejas fuera de los números configurados.
- Variables del texto: `{{contact.first_name}}`, `{{contact.name}}`, `{{agent.first_name}}`.
- El mensaje sale marcado con `content_attributes.arroyo_kind = window_nudge`: no cuenta como atención y el bot de n8n no lo toma (solo responde entrantes en conversaciones `pending`).

Recordatorio de Meta: un mensaje del negocio no reabre la ventana; solo invita a responder. Por eso es uno por ventana.

## Deploy

1. Mergear y desplegar como siempre (respaldo previo de la base). Hay **una migración aditiva**: `arroyo_opportunities.origin` (jsonb, por defecto `{}`).
2. Completar datos anteriores (no manda mensajes ni reasigna; se puede repetir):
   `ACCOUNT_ID=1 bundle exec rake arroyo:commercial:board_backfill`
   - origen: el anuncio guardado en cada conversación pasa a su primera consulta;
   - perdidas: las consultas abiertas cuya conversación recibió la etiqueta de perdida durante la consulta.
3. Ajustes → Arroyo → *Embudo del panel*: revisar etiquetas, números y horas; prender el interruptor general. Requiere el embudo comercial prendido.
4. El aviso de ventana, recién después de revisar el texto. Conviene probarlo primero con un solo número.

Para volver atrás: apagar el interruptor de la sección. El panel vuelve al embudo anterior; los datos de origen quedan guardados.

## Código

- Configuración: `app/models/arroyo/funnel_board_config.rb` (incluido en `Arroyo::Setting`), `settings/components/FunnelBoardSection.vue`.
- Datos: `Arroyo::Commercial::Board` (+ `BoardRow`, `BoardFlow`, `BoardOrigins`), `Api::V1::Accounts::Arroyo::BoardController` (`/arroyo/commercial/board`, `/opportunities`, `/export`).
- Origen: `Arroyo::Commercial::Origin`, `Arroyo::Ads::ReferralRecorderService` (`ad_referral_at`), `Arroyo::Ads::CampaignResolverJob`.
- Abandonadas y aviso: `Arroyo::Commercial::Abandonment`, `WindowNudgeSchedule`, `WindowNudgeService`, `WindowNudgeJob` (`config/schedule.yml`).
- Recompra: `Arroyo::Commercial::RepurchaseLabelService`. Backfill: `Arroyo::Commercial::BoardBackfillService`.
- Pantalla: `panel/components/board/` (`FunnelBoard`, `FlowChart`, `SellerTables`, `OriginsTable`, `BoardExtras`).
