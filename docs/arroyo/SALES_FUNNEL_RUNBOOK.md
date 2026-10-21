# Embudo comercial: uso y habilitación

Implementación en `arroyo/dev`, iniciada el 20/10/2026. Actualización 21/10: integración Git autorizada y parches guardados en los borradores remotos de n8n, todavía sin publicar. El despliegue lo realiza Mauro. Ver [RELEASE_2026_10_21.md](RELEASE_2026_10_21.md). Facturación queda fuera de esta etapa.

## Qué revisar en local

En Panel de vendedores → Actividad, seleccionar la bandeja **DEMO LOCAL · Embudo comercial** y los últimos siete días. Enlace del entorno preparado: http://localhost:3300/app/accounts/1/arroyo/panel?preset=last_7_days&group_by=day&inbox_ids=110.

Hay once oportunidades sintéticas: bot, sin asignar, pendiente de Juli, gestión de Marcos, ganada, perdida, cliente sin respuesta, traspaso, recompra y postventa fallida. La recompra aporta dos oportunidades en una conversación. Los contactos de demostración usan `arroyo.test`; los estados de entrega son datos simulados, sin envíos a clientes.

- Las tarjetas y las cifras del recorrido abren listas con los mismos filtros. Los estados actuales suman el total; derivadas, atendidas y atrasos son indicadores adicionales.
- El recorrido usa la fecha de ingreso. El gráfico «Actividad realizada» y la tabla diaria usan la fecha de cada evento. Cambiar la métrica conserva este criterio en el detalle y CSV.
- «Sin respuesta del vendedor» significa cuatro horas laborables sin atender el primer mensaje pendiente. Transferir o enviar una automatización no reinicia el reloj.
- «Cliente dejó de responder» requiere atención humana previa, tres seguimientos identificados con entrega o lectura confirmadas y dos fechas locales de espera. Un envío fallido o sin entrega confirmada no prueba silencio del cliente.
- «Registrar venta» y «Marcar perdida» guardan el resultado. «Nueva oportunidad» requiere confirmar otra intención de compra; una respuesta de garantía o postventa no genera otra venta.
- Al comenzar otra oportunidad en el mismo chat, solo se interrumpen etapas anteriores de postventa todavía sin intentar. Se conservan la compra, los mensajes y las tareas manuales previas.

El script `script/arroyo/commercial_demo.rb` solo admite desarrollo. Usa el adaptador de jobs de pruebas durante su ejecución y una bandeja API local; no configura credenciales Meta ni demuestra entrega real. La muestra presupone los vendedores locales 4 y 5. No ejecutar este script en producción.

## Configuración

En Ajustes → Arroyo → Panel de vendedores:

| Opción | Valor inicial | Función |
| --- | --- | --- |
| Panel | Conserva configuración existente | Permite consultar el panel. |
| Embudo comercial | Apagado | Registra oportunidades y habilita el reporte nuevo. |
| Reparto con historial | Apagado | Delega la selección del vendedor a Chatwoot. Requiere embudo. |
| Vendedores comerciales | Sin selección | Usuarios de la cuenta que participan en atención y reparto. |
| Plazo de respuesta | 4 horas | Horas de atención antes de señalar un atraso. |
| Historial de reparto | 7 días | Ventana de adquisiciones efectivas para equilibrar asignaciones. |

Calendario inicial: lunes a sábado, 08:30–12:00 y 16:30–20:30, en la zona horaria del negocio. No hay calendario de feriados. Las tomas manuales y los traspasos cambian el responsable efectivo y el reparto posterior. Las ventas ya registradas conservan su vendedor.

Los flags nuevos están apagados por defecto. Se habilitaron únicamente en la cuenta local de demostración. No es necesario pagar Captain para usar estas funciones Arroyo.

## Histórico y publicación posterior

La reconstrucción explícita se ejecuta con `ACCOUNT_ID=<id> bundle exec rake arroyo:commercial:backfill`. Reconstruye ingresos comprobables y compras existentes, marca cobertura parcial y no envía mensajes ni reasigna. No inventa atención humana a partir de un emisor User histórico ni crea postventa retroactiva por una etiqueta vieja.

Orden de despliegue, cuando se autorice:

1. Desplegar Chatwoot y ejecutar las dos migraciones nuevas, con los flags nuevos apagados.
2. Verificar la configuración y, si corresponde, reconstruir el histórico de la cuenta explícita. Revisar volumen y tiempos antes de habilitar el reporte general.
3. Preparar una prueba aislada de n8n con destinatarios propios; este proyecto no presupone una rama llamada staging. Seguir `n8n/commercial-funnel-deploy.md` y comprobar las versiones publicadas antes de aplicar el parche.
4. Publicar los marcadores y la integración de n8n con flags apagados. Verificar saludos, origen de mensajes, respuesta real del cliente y contratos de asignación/envío.
5. Habilitar embudo y luego reparto con historial, tras comprobar la integración. Conservar las plantillas Meta y los dos días entre seguimientos. Postventa mantiene su consulta cada quince minutos.

Para volver al funcionamiento anterior, apagar primero reparto con historial y después embudo, dejando terminar derivaciones en curso. Se conserva el historial y el panel anterior. No activar dos repartidores para una misma derivación.

## Verificación disponible

- RSpec de servicios, modelos, listeners y APIs Arroyo, con base aislada `arroyo_commercial_test`.
- Vitest de panel, filtros, acciones, permisos visibles y ajustes; Node de los parches n8n; RuboCop y ESLint de archivos tocados.
- Revisión independiente con correcciones de recompra, mensajes antiguos, permisos, alertas entre compras y borrado nativo.
- La revisión visual inicial mostró el panel y los once casos. La pasada visual final de escritorio/móvil quedó pendiente porque el navegador local está deshabilitado en Work. No se certifica aún esa pasada ni una prueba integral remota Meta/n8n.
- Los ensayos locales no certifican carga de producción ni concurrencia masiva. La habilitación debe incluir medición del rango y volumen reales en el entorno aislado.

### Resultados del 20/10/2026

| Comprobación | Resultado |
| --- | --- |
| RSpec Arroyo, pasada final independiente | 101 ejemplos, cero fallos. |
| Vitest panel/ajustes | 47 pruebas aprobadas. |
| Node seguimientos/postventa/parche comercial | 32 pruebas aprobadas. |
| RuboCop código Ruby tocado | 37 archivos sin infracciones; esquema generado excluido. |
| ESLint JS/Vue tocado | Sin errores ni advertencias. |
| Traducciones es/en | Claves equivalentes y ayudas contextuales presentes. |
| API de la muestra local | Reporte, oportunidades, contextos y CSV: 200. Once oportunidades y once filas CSV. |
| Acceso HTTP local | `localhost:3300/app/login`: 200. |
| RSpec ampliado Arroyo + conversaciones/bot/dispatcher nativos | 214 ejemplos, dos fallos en autoasignación nativa. |
| Control sin el hook comercial nuevo | Los mismos dos fallos se reproducen cargando el dispatcher de HEAD anterior dentro del proceso de test: cuatro ejemplos, dos fallos. |

Los dos casos nativos están en `spec/models/concerns/auto_assignment_handler_shared.rb`, líneas 25 y 48: esperan asignación inmediata. Stubbean `Redis::Alfred.rpoplpush`, pero la implementación nativa vigente selecciona desde `lrange`/intersección. No se alteraron el modelo Conversation ni los servicios nativos de autoasignación para ocultar esos fallos. Este resultado no equivale a certificar una suite nativa completamente verde.

Se verificó además que una venta registrada por un administrador conserva al vendedor comercial, mientras el evento audita al administrador. Se corrigió una aserción Arroyo de singleton para comparar el nombre de clase y tolerar la recarga que la configuración de tests permite.
