# Comentarios públicos — plan de implementación

> Para ejecución: usar superpowers:executing-plans, en esta sesión, sobre el alcance expresamente autorizado por el usuario.

**Goal:** vendedores atienden comentarios públicos desde Chatwoot; n8n importa y publica respuestas, con Meta pendiente de configurar.
**Architecture:** inbox API nativo + tablas/servicios Arroyo + cola de publicación reclamada por n8n.
**Tech Stack:** Rails 7.1, PostgreSQL 16, Vue 3, Tailwind, n8n SDK/MCP.
**Spec:** [SOCIAL_COMMENTS_DESIGN.md](SOCIAL_COMMENTS_DESIGN.md).

## Restricciones y revisión

Namespace y tablas Arroyo; flag apagado por defecto; es/en; hooks core comentados; no editar enterprise. Preservar notas privadas, DM y postventa. Firmas deben usar bytes originales; duplicados no crean mensajes ni respuestas extra; no publicar texto de bot; timeout no autoriza reenvío; permisos por cuenta/inbox también en callbacks.

## Tareas

- [x] 1. Base de datos y servicios: migración nueva, SocialChannel/Comment/Reply, firma y parser Meta, importación/enriquecimiento, creación de respuesta, claim/ack/retry. Primero specs fallidos en `spec/services/arroyo/social_comments/` y modelos; luego implementación mínima y prueba verde.
- [x] 2. API y hooks: controlador/policy/presenter Arroyo, routes, settings/features, MessageBuilder y controlador de mensajes. Specs de requests y builder: no autenticado, cuenta ajena, inbox ajeno, API key/bot, nota privada, idempotencia y publicación deshabilitada. Verificar contratos verify/ingest/enrich/claim/ack/retry.
- [x] 3. UI: módulo `routes/dashboard/arroyo/comments`, API/composable, sidebar/ruta, banner ReplyBox y etiqueta de publicación en components-next. Vitest: advertencia pública, configuración pendiente, filtros, errores/reintentos y continuidad de canales normales. Mantener componentes y estilos nativos con Tailwind.
- [x] 4. n8n: obtener tipos reales y SDK; crear subworkflow de procesamiento, entrada Meta GET/POST y worker programado en el proyecto Arroyo, solicitando carpeta v3. Validar nodos/SDK, probar con pin data, conservar borradores sin credenciales ni activación. Guardar código y contratos sin secretos en `docs/arroyo/n8n/`. El conector devuelve carpeta null al releer; ubicación pendiente de confirmar en n8n.
- [x] 5. Local y cierre: arrancar Docker, base separada, migrar, habilitar flag solo local y cargar ejemplos ficticios. Verificar UI, API y red aislada. RSpec focalizado + hooks core, Vitest y lint; documentar resultados y pasos finales de Meta en runbook.

## Registro

- 14/10/2026: creado worktree desde arroyo/dev; los cinco cambios locales previos permanecen en el checkout original. Rama de trabajo arroyo/comments. Ejecución directa autorizada por el usuario; se conserva como pendiente la configuración/publicación real de Meta.
- Servicios: RED por módulo ausente; implementación inicial verde 19 ejemplos. Revisión independiente detectó tres hallazgos reproducidos en 3 pruebas rojas: macros con User, edición con timestamp igual y representación nativa de publicación incierta. Corregidos y cubiertos; regresión final de 70 ejemplos Ruby, 0 fallos, con archivos estables.
- Interfaz: helper RED por archivo ausente y GREEN; 32 pruebas de comentarios/panel existentes verdes; después de la corrección de estado público se revalidaron las 9 pruebas de comentarios y se agregó una prueba verde de la pantalla completa/filtros/enlace nativo. Total verificado: 33 pruebas frontend. ESLint y RuboCop (23 archivos) sin infracciones.
- n8n: 3 SDK validados y borradores creados por MCP, active:false y ninguna credencial autoasignada. Simulaciones exitosas: publicación con ID, resultado sin ID, enriquecimiento, challenge GET, POST binario rechazado y cola vacía. Bytes originales comprobados en la ejecución 613025; lógica pura de errores/redacción/timeouts comprobada con verify.mjs.
- Local: Docker/Rails/Vite/gateway activos, login/API/contexto de 2 comentarios ficticios verificados y red interna confirmada. Pendiente del punto 5: revisión visual manual en Chrome; el navegador integrado no completó la carga. Instrucciones y pasos restantes de Meta en SOCIAL_COMMENTS_RUNBOOK.md.
- Seguimiento de la pantalla blanca: reproducida en navegador y compilación aislada, corregido el runtime local y verificado el formulario de acceso, panel autenticado y editor real del comentario de ejemplo. Se completa el punto 5. Los cambios del runtime privado se guardan en `carpeta levantar local`; no cambian código de producción ni activan Meta. Ver detalles, sincronización y mediciones en el runbook.
