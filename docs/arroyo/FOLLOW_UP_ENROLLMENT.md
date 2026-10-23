# Seguimiento comercial: inscripción y calendario

21/10/2026. Implementación desarrollada en `codex/followup-enrollment`, basada en `arroyo/main` (`e5901ea70f`), para integración local en `arroyo/main`. Pendientes: push, despliegue de Chatwoot y publicación n8n. No se modificaron conversaciones de producción ni se enviaron pruebas a clientes.

## Funcionamiento para vendedores

- La inscripción es siempre manual: un nuevo contacto no recibe `seguimiento` por sí solo. Al agregar la etiqueta se programa el primer mensaje para el día siguiente a las 10:00 de Argentina, también en conversaciones anteriores. No exige atención humana previa. Mantener una inscripción activa o cambiar otras etiquetas no reinicia las fechas ni los contadores.
- Se usan exclusivamente las plantillas Meta `seg_dia_1`, `seg_dia_3` y `seg_dia_5`. Entre envíos hay dos días calendario. El domingo pasa al lunes y el siguiente paso conserva dos días desde el envío efectivo.
- Las respuestas del cliente y los mensajes del vendedor no detienen, reinician ni reemplazan el seguimiento. Las métricas de atención se calculan de forma independiente.
- Quitar `seguimiento` cancela los pasos pendientes. Otro mensaje del cliente no vuelve a activarlo. Volver a agregarla programa para el día siguiente los pasos todavía no realizados, sin repetir los enviados.
- Tras los tres mensajes y dos días adicionales se retira `seguimiento`. `inactivo` y «Cliente dejó de responder» siguen exigiendo entrega/lectura confirmada, atención humana previa y ausencia de respuesta posterior; completar una secuencia no demuestra abandono.
- Se mantienen las exclusiones por venta/pérdida, contacto bloqueado o `no-contactar`, y los requisitos de WhatsApp Cloud y vendedor comercial válido. No cambia postventa D+1/D+7/D+30 ni el reparto.
- No se recuperan automáticamente etapas vencidas de días anteriores. Se revisan explícitamente para evitar envíos masivos atrasados.

Ejemplo: etiqueta agregada el martes 20/10 → envíos miércoles 21, viernes 23 y lunes 26 (el domingo 25 se omite).

## Implementación

`FollowUpEnrollment` captura los cambios de etiqueta `seguimiento`; `FollowUpSchedule` centraliza inscripción, pausa, fecha elegible y cierre. Usa eventos `follow_up_enrolled`/`follow_up_stopped`; la inscripción solo ocurre al agregar la etiqueta. Se reutilizan las tablas existentes: no hay migraciones nuevas.

Los contextos incluyen `follow_up.active`, `next_at`, `due` y `finish_due`. El endpoint idempotente de envío vuelve a validar elegibilidad bajo bloqueo para respetar cancelaciones posteriores a la lectura de n8n. El cierre usa `POST /arroyo/commercial/follow_up/complete` bajo bloqueo y conserva las etiquetas ajenas.

Al incorporar historia se importan los contadores heredados descontando mensajes ya registrados. Sin fecha válida de un envío anterior no se adivina la agenda ni se repite el primer paso. Las oportunidades de recompra confirmadas mantienen contadores independientes.

## Publicación coordinada pendiente

1. Integrar y desplegar Chatwoot antes de publicar n8n. No hay migraciones nuevas.
2. Preparar el parche desde una lectura actual: `node docs/arroyo/n8n/follow-up-enrollment-build.cjs <workflow-sanitizado.json>`. El archivo generado está fijado a la versión publicada `975523d4-9926-438c-ad58-e80769f15757`; releer si cambió.
3. Publicar únicamente sus tres operaciones: clasificador y URL/cuerpo de `Cerrar Secuencia`. No reaplicar el parche histórico completo `commercial-funnel-operations.json` a un workflow que ya lo recibió.
4. Comprobar contextos y una corrida natural. No ejecutar manualmente el workflow contra clientes para probar.

## Conversaciones ya etiquetadas antes del despliegue

La tarea consulta IDs explícitos, conserva el instante original de la etiqueta y **no escribe por defecto**:

```sh
ACCOUNT_ID=1 CONVERSATION_IDS=10295 bundle exec rake arroyo:commercial:enroll_followups
```

Solo después de revisar la salida y autorizar cambios sobre esos registros, `APPLY=1` registra la inscripción. No envía mensajes ni cambia asignaciones. Si la fecha ya venció, no se recupera automáticamente: requiere una decisión explícita antes de reprogramar o de quitar/volver a agregar la etiqueta. No aplicar a todos los chats por omisión ni inventar respuestas humanas del histórico.

## Verificación

Validación final: 128 ejemplos Rails y 37 pruebas Node aprobados; RuboCop (12 archivos) y ESLint (4 archivos) sin infracciones. Pruebas locales con `arroyo_commercial_test`, datos sintéticos y WebMock: inscripción, calendario, plantillas, idempotencia, permisos, cancelación posterior a lectura de contextos, histórico, eliminación nativa y consulta previa. Los ensayos no certifican entrega Meta ni despliegue en producción.

## Envío desde Chatwoot (reemplaza al cron diario de n8n)

Con `follow_up.enabled` activo en la configuración de Arroyo, `Arroyo::Commercial::FollowUpJob` corre todos los días a las 10:00 de Argentina (`config/schedule.yml`, `0 10 * * * America/Argentina/Buenos_Aires`). Para cada cuenta con embudo y seguimiento activos, `FollowUpDispatchService` envía el paso que toca (`due?`) por el mismo `FollowUpMessageService` que usaba n8n y cierra las secuencias terminadas (`finish_due?`). Un fallo en un chat se registra y no frena a los demás. El envío es idempotente por paso: si n8n y el job corren a la vez no se duplica nada.

- **Firma de la plantilla:** `follow_up.aliases` asocia el nombre del agente en Chatwoot con el nombre con el que firma (preconfigurado: Julieta Peralta → Juli, Marcos Peralta → Marcos). Sin alias se usa el nombre completo. El producto sale de las etiquetas (`bici` → «una bicicleta», `aparatosgim` → «equipamiento de gimnasio», sin rubro → «lo que estabas viendo»).
- **Panel «Seguimientos»** (`/arroyo/seguimientos`, administradores; la pantalla de ventanas de 24 hs pasó a llamarse «Ventanas de 24 hs», `/arroyo/ventanas`): estados (programados, por cerrar, terminados, pausados, con etiqueta sin inscribir), pasos enviados con su entrega, agenda por día y el motivo por el que un chat no sale. Acciones: enviar ahora, reprogramar el próximo envío (solo a días posteriores a hoy; vale hasta que sale ese mensaje) e inscribir chats con etiqueta que nunca se inscribieron (primer envío al día siguiente a las 10:00).
- **Postventa no cambia:** sigue disparándose desde el cron de 15 minutos de n8n.

### Corte de n8n

1. Desplegar Chatwoot y probar el panel con `follow_up.enabled` apagado.
2. Encender `follow_up.enabled` (Ajustes de Arroyo). Mientras n8n siga activo no hay duplicados, pero conviene apagar su rama diaria el mismo día.
3. Desactivar en el workflow «arroyo v3 · seguimientos post-venta» el trigger «Diario 10hs ART» y su rama. No desactivar el workflow completo: contiene «Postventa Cada 15 Minutos».
4. Inscribir desde el panel los chats que tienen la etiqueta `seguimiento` sin inscripción (la inscripción automática ya no existe).

