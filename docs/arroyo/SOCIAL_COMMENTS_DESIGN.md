# Comentarios públicos atendidos por vendedores

Alcance confirmado el 14/10/2026: Instagram y Facebook, respuestas humanas desde Chatwoot, sin bot. Preparar aplicación, workflows y pruebas; configurar credenciales, permisos y callbacks de Meta al final. Zoho y UTMs quedan fuera de este trabajo.

## Flujo y responsabilidades

Se reutilizan inboxes API nativos, sin bot asociado. Una configuración Arroyo vincula cada inbox a una cuenta profesional/página de Meta. Los comentarios de un mismo hilo comparten conversación; cada mensaje entrante conserva el identificador externo del comentario y la publicación. El vendedor usa la conversación normal para responder, con aviso persistente de respuesta pública y enlaces al origen.

Chatwoot verifica la firma HMAC del cuerpo original recibido de Meta, controla cuenta/inbox, importa sin duplicados y guarda la cola de respuestas. n8n recibe el webhook, importa mediante HTTP en Chatwoot y confirma a Meta después de guardarlo. Luego ejecuta el subworkflow para enriquecer enlaces. Un disparador programado reclama respuestas humanas y ejecuta ese mismo subworkflow para publicarlas. No se conectan estos workflows al bot de WhatsApp.

## Datos y contrato

- `arroyo_social_channels`: account, inbox API, platform (`instagram`/`facebook`), external_account_id, api_version, publishing_enabled (false por defecto).
- `arroyo_social_comments`: account, channel, conversation y message nativos; remote_id, thread_id, parent_id, author_id/name, body, media_id, post_url, comment_url, remote_updated_at, deleted_at. Unicidad channel/remote_id.
- `arroyo_social_replies`: account, comment, message, sender humano, client_request_id; estados pending_configuration, queued, publishing, published, failed, unconfirmed; claim_token, claimed_at, published_at, remote_reply_id, error_message. Unicidad por mensaje y por comentario/client_request_id.
- API bajo `/api/v1/accounts/:account_id/arroyo/social_comments`: channels (GET/POST/PATCH), comments (GET), conversation context (GET), verify (GET), ingest (POST), enrich (POST), claim (POST), acknowledge (POST), retry (POST).
- Integración (verify/ingest/enrich/claim/acknowledge) requiere administrador; vendedores solo ven inboxes autorizados. Reintentar requiere acceso al inbox. Ingest exige cuerpo base64 sin modificar y `X-Hub-Signature-256` válido, además de la autenticación Chatwoot.
- `ARROYO_SOCIAL_COMMENTS_META_APP_SECRET` y `ARROYO_SOCIAL_COMMENTS_META_VERIFY_TOKEN` se configuran en servidor, nunca se exponen en la UI ni en la cola. Tokens Graph se guardan en credenciales n8n tipadas. El nodo Graph usa Facebook Login para ambas redes; otras modalidades requieren un adaptador explícito.

## Publicación exclusivamente humana

Un hook puntual en MessageBuilder intercepta solo mensajes públicos salientes del inbox configurado. El servicio exige sender User autorizado, texto, ausencia de automatización y contexto de creación directa desde una sesión autenticada. El contexto es interno y no puede enviarse como parámetro ni pasar a jobs/macros. Las notas privadas conservan el pipeline nativo. El controlador de mensajes rechaza crear respuestas públicas de estos inboxes mediante API keys de integración. El resto de los canales conserva el comportamiento nativo. SendReplyJob evita notificaciones de email del canal API en estos inboxes.

Sin configuración, la respuesta se guarda como pending_configuration y no será publicada al habilitar Meta: el vendedor debe solicitar el reintento explícitamente. Con configuración, se guarda queued; claim cambia atómicamente a publishing con token por intento. Ack exitoso exige el ID devuelto por Meta. Fallos definitivos quedan failed; timeout/resultado ambiguo o claim vencido quedan unconfirmed y nunca se reintentan automáticamente. Una confirmación repetida del mismo intento es idempotente.

Los eventos propios se ignoran para evitar ecos. Comentarios editados actualizan el registro; los eliminados conservan evidencia y no admiten nuevas respuestas. URLs de publicaciones/comentarios solo permiten HTTPS de Instagram/Facebook. Ni la interfaz ni n8n interpretan mensajes entrantes como instrucciones para publicar.

## UI y compatibilidad

Nueva entrada Arroyo «Comentarios», detrás de flag por cuenta apagado por defecto. Lista filtrable por red y estado, acceso a la conversación y configuración administrativa básica de inboxes. Banner en la conversación: «Las respuestas son públicas», contexto de publicación y situación de conexión. Estado específico en cada respuesta pública: pendiente, publicando, publicada, fallida o sin confirmar; no afirmar entrega/lectura de un comentario.

Hooks core: MessageBuilder, Conversations::MessagesController, SendReplyJob, dashboard.routes, Sidebar, ReplyBox y MessageMeta de components-next. Cada hook lleva `ARROYO:`. No editar enterprise ni eliminar funcionalidades nativas.

## Configuración final y pruebas locales

Preparar workflows como borradores, con credenciales pendientes y sin activar envíos. No reemplazar callbacks de las integraciones nativas de DM: usar una app de Meta separada para comentarios, o un distribuidor verificado si luego se decide compartirla. La configuración final incluye página/cuenta profesional, versión Graph, permisos/aprobación, secretos de firma y credenciales Graph/Chatwoot.

El entorno local usa base y puertos propios y red sin salida; los ejemplos tienen autores y publicaciones ficticios. Las pruebas cubren firmas, separación entre cuentas/inboxes, deduplicación, hilos, exclusión de bots, notas privadas, estados/claims/callbacks, caducidad y resultados ambiguos. Los workflows se validan por MCP y se prueban con pin data, sin llamadas reales a Meta.
