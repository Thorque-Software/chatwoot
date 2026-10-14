# Comentarios públicos: uso local y conexión final

## Implementación

Rama de trabajo `arroyo/comments`, creada desde `arroyo/dev` en un worktree aislado. No se modificaron los cinco cambios locales previos del checkout principal ni se desplegó producción.

Los vendedores atienden comentarios de Instagram y Facebook en bandejas API dedicadas. El módulo **Comentarios** lista comentarios, permite filtrar por red/estado y abre la conversación nativa. El editor advierte que la respuesta será pública; las notas privadas conservan el comportamiento nativo. Los administradores habilitan la función en Configuración → Arroyo y crean bandejas con vendedores asignados. El flag viene apagado por cuenta.

Solo la creación directa desde una sesión autenticada habilita el contexto de respuesta humana. Un `User` como remitente no basta: macros, bots, reglas y API keys no obtienen ese contexto. Los inboxes nuevos no tienen bot, webhook de canal ni autoasignación, y sus conversaciones entran abiertas. La publicación solo admite texto.

El estado público es independiente del `sent` nativo del inbox API. **Publicada en Meta** exige un ID devuelto por Meta; no implica entrega ni lectura. Los resultados inciertos se muestran como **Publicación sin confirmar**, sin el error/reintento genérico de mensajería privada.

## Probar en esta computadora

- URL: <http://localhost:3300/app/accounts/1/arroyo/comments>.
- Cuenta local: `admin.local@arroyo.test`; contraseña en el archivo privado `carpeta levantar local/login.local.json` del checkout principal.
- Iniciar/reiniciar: ejecutar `carpeta levantar local/Start-Comments.ps1` en PowerShell con Docker Desktop iniciado.
- Detener solo esta instancia: `carpeta levantar local/Stop-Comments.ps1`.
- Diagnóstico de login/API sin mostrar credenciales: `carpeta levantar local/check-comments.ps1`.
- Fuente montada: worktree `C:/Users/mauro/.codex/worktrees/arroyo-comments/chatwoot`. Rails en 3300 y Vite/HMR en 3336.
- Base separada `arroyo_comments_local`, Redis DB 2, PostgreSQL/Redis del entorno local existente. Red de aplicación interna sin salida a Internet. Gateway publicado exclusivamente en loopback. Sidekiq no se inicia automáticamente.
- Dos comentarios ficticios identificados como ejemplo, uno por red; una respuesta guardada pendiente de conexión. Publicación desactivada en ambas bandejas. No se envía nada a Meta.

Abrir el comentario de ejemplo, comprobar la advertencia pública y enviar una respuesta de prueba. Debe quedar pendiente de conexión, sin constancia de publicación. Cambiar a nota privada y comprobar que desaparece la advertencia. Volver a Comentarios y actualizar para ver el seguimiento. La conexión real queda para el siguiente paso.

## Borradores n8n creados por MCP

Proyecto confirmado: **Arroyo Fitness <arroyo@thorque.com.ar>**, ID `a7I07ia1D38hsGNd`.

| Flujo | Enlace | Función |
|---|---|---|
| Subworkflow | [Abrir](https://n8narroyo.thorque.com.ar/workflow/URLYZDOrdxjt5LnP) | Publicar una respuesta humana o consultar el enlace de una publicación; confirmar el resultado en Chatwoot. |
| Webhook Meta | [Abrir](https://n8narroyo.thorque.com.ar/workflow/IQ5u9EC4W6s4fnAg) | Verificación GET y recepción POST con cuerpo binario original. Importar antes de confirmar a Meta; enriquecer enlaces después. |
| Cola vendedores | [Abrir](https://n8narroyo.thorque.com.ar/workflow/buLHjnIBKTRyy9zs) | Reclamar intentos pendientes cada minuto y ejecutar el subworkflow una vez por respuesta. |

Se solicitó la carpeta v3 `VNj5ZKYNCAvJBHkb` al crear los tres. El MCP confirma el proyecto pero devuelve `parentFolderId: null` al releer; verificar su ubicación en la interfaz de n8n durante la configuración final. Los enlaces anteriores permiten encontrarlos sin depender de la carpeta.

Los tres tienen `active: false`, sin credenciales autoasignadas. No se cambiaron los workflows existentes. Código reproducible en `docs/arroyo/n8n/comments/*.sdk.js`; comprobación de lógica pura: `node docs/arroyo/n8n/comments/verify.mjs`.

### Contrato con Chatwoot

Base configurada en los borradores: `https://chatarroyo.thorque.com.ar/api/v1/accounts/1/arroyo/social_comments`. Revisar dominio/cuenta antes de activarlos. Nunca apuntar borradores remotos a localhost.

| Método/ruta | Entrada / resultado |
|---|---|
| GET `verify` | `hub.mode`, `hub.verify_token`, `hub.challenge`; challenge JSON únicamente si coincide el token configurado. |
| POST `ingest` | `payload_base64`, `signature`; HMAC SHA256 del cuerpo original validado por Rails. Responde `{accepted, posts}`. |
| POST `enrich` | `channel_id`, `media_id`, `post_url`; enlace HTTPS de dominios Meta permitidos. |
| POST `claim` | Devuelve `{replies: [...]}`; cada intento contiene `id`, `claim_token`, `platform`, `api_version`, `remote_comment_id`, `content`. |
| POST `replies/:id/acknowledge` | `claim_token`, `status`, `remote_reply_id`, `error_message` genérico sin secretos. |
| POST `replies/:id/retry` | Solo sesión humana autorizada y fallo definitivo/pendiente de configuración. |

Todos requieren autenticación y cuenta correcta. Verify, ingest, enrich, claim y acknowledge requieren administrador. Los endpoints de lectura respetan pertenencia al inbox; los administradores ven la cuenta completa.

## Configuración de Meta pendiente

1. Desplegar primero esta versión de Chatwoot y ejecutar las migraciones. Dejar publicación por canal apagada.
2. Configurar en Rails `ARROYO_SOCIAL_COMMENTS_META_APP_SECRET` y `ARROYO_SOCIAL_COMMENTS_META_VERIFY_TOKEN` con los valores de la app de comentarios; no guardarlos en Git ni en parámetros de nodos. Si se usan contenedores, aplicar las variables tanto a web como a procesos Rails correspondientes.
3. En n8n, asignar una credencial Header Auth **Arroyo Chatwoot Comentarios**, cabecera `api_access_token`, con el token de un administrador de la cuenta. Asignarla solo a nodos de Chatwoot.
4. Asignar credenciales tipadas Facebook Graph API **Arroyo Meta Instagram Comentarios** y **Arroyo Meta Facebook Comentarios** a sus nodos respectivos. Los borradores usan `graph.facebook.com`: se prepararon para Instagram profesional vinculado a una página mediante **Facebook Login**. Si la app existente usa Instagram Login y `graph.instagram.com`, adaptar el transporte antes de habilitarlo.
5. Verificar permisos vigentes, activos vinculados y suscripción `comments` para Instagram y `feed` para la página. Validar permisos y tokens con la app real: el acceso a DM por sí solo no demuestra acceso a comentarios.
6. Usar app/callback de comentarios separado del existente de DM, o un distribuidor validado que preserve las suscripciones anteriores. No reemplazar a ciegas el callback de los mensajes directos. Nuevo callback: `https://n8narroyo.thorque.com.ar/webhook/arroyo-v3-public-comments`, GET/POST.
7. Habilitar el flag de comentarios en la cuenta; crear/configurar bandejas, ID real de cada cuenta/página y versión Graph admitida por la app. Mantener publicación apagada.
8. Publicar primero subworkflow y entrada, verificar challenge/firma y recibir un comentario de prueba real en cada red. Confirmar autor, texto, hilo, enlace y ausencia de bot.
9. Habilitar publicación en cada canal, publicar worker y enviar una respuesta de un vendedor sobre una publicación de prueba. Verificar el ID de Meta y su aparición pública antes de usarlo con clientes.
10. Las respuestas preparadas sin conexión no se publican al habilitar el canal: requieren reintento manual explícito. Probar también el rechazo de permisos y la conservación de notas/DM existentes.

### Resultados inciertos

No activar reintentos automáticos del POST a Graph ni usar «Retry execution» de n8n para repetir una publicación incierta. Error 5xx, timeout, ausencia de ID o claim vencido se conservan sin confirmación; revisar directamente en Meta antes de cualquier nueva respuesta. Un fallo definitivo puede reintentarse desde Chatwoot tras corregir la causa. Desactivar el flag o la publicación del canal detiene nuevas reclamaciones; una petición ya iniciada puede completar y su callback se conserva.

## Verificaciones del 14/10/2026

- RSpec final: **70 ejemplos, 0 fallos**. Servicios/controlador de comentarios, settings/features, MessageBuilder y SendReplyJob.
- Vitest: **33 pruebas verificadas** entre comentarios y panel existente. La última modificación de estados públicos se revalidó en los 9 tests de comentarios; la pantalla completa tiene una prueba adicional de montaje, filtros y enlace nativo.
- RuboCop: 23 archivos sin infracciones. ESLint de archivos JS/Vue afectados sin errores.
- SDK/nodos n8n validados por MCP; ejecuciones simuladas 612985, 613015, 613017, 613025, 613109 y 613114 exitosas. Lógica pura verificada con `verify.mjs`. Ninguna prueba hizo solicitudes reales a Meta.
- Login local, flags, listado y contexto de los dos ejemplos verificados por HTTP. PostgreSQL separado y red de aplicación interna confirmados.
- La revisión visual manual sigue pendiente: el navegador integrado quedó en blanco/no completó navegación. El servidor y los módulos de Vite respondieron HTTP 200; la pantalla se montó correctamente en Vitest. Abrir desde Chrome para la revisión del usuario.

Referencias para la configuración final: [comentarios de Instagram](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/comment-moderation/), [comentarios Graph](https://developers.facebook.com/docs/graph-api/reference/object/comments/), [webhooks Meta](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/) y [webhook raw body de n8n](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/). La documentación Meta devolvió límites de acceso durante esta sesión; la validación real de permisos y versión permanece pendiente.
