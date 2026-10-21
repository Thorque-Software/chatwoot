# Panel comercial Arroyo: embudo, atención y recompra

Fecha: 20/10/2026. Rama: `arroyo/dev`.
Estado: diseño aprobado e implementado en local sobre `arroyo/dev`. Verificación y habilitación: [SALES_FUNNEL_RUNBOOK.md](SALES_FUNNEL_RUNBOOK.md). Publicación pendiente.

## Objetivo y alcance acordado

Mostrar en Actividad del Panel de vendedores el recorrido de las consultas, la intervención real de Juli y Marcos, sus resultados y las incidencias que necesitan acción. Cada cifra debe abrir el listado que la explica; consultar por vendedor y por día no debe exigir entrar chat por chat.

Decisiones confirmadas en la conversación:

- Facturación queda fuera de esta etapa, incluidos campos de importes e integraciones contables.
- Separar falta de respuesta del vendedor y falta de respuesta del cliente.
- La atención del vendedor vence tras cuatro horas dentro del horario de atención. Los mensajes automáticos no reinician el plazo.
- Una nueva oportunidad en un chat que ya tuvo una venta requiere confirmación del vendedor. Una respuesta a postventa, garantía o agradecimiento no confirma una nueva oportunidad ni una venta.
- Mantener las plantillas exclusivas de Meta y la separación de dos días del seguimiento comercial.
- Trabajar en `arroyo/dev` y evaluar en local antes de cualquier publicación.

El diseño amplía el registro comercial dentro del namespace Arroyo. Cambiar solo etiquetas y gráficos conserva los problemas de atribución y recompra; incorporar otro CRM agrega una integración innecesaria para este alcance.

## Evidencia del estado actual

Fuentes locales: `app/services/arroyo/agent_panel/{report_builder,scopes,filters}.rb`, `app/listeners/arroyo/assignment_listener.rb`, `app/models/arroyo/{assignment_event,post_sale_purchase}.rb`, `app/services/arroyo/post_sale/{register_purchase_service,message_service}.rb` y `panel/components/ActivityTab.vue`.

Fuentes de n8n leídas mediante MCP el 20/10:

- `B5YmsSniVco8DT6Y`, versión publicada `45100a85-4f3c-474d-a029-08e6ea6f8857`: `Tomar Turno` incrementa Redis; `agents1` alterna los IDs 4/5. No incorpora tomas manuales ni traspasos.
- `fF0LK453uWJdBHsR`, versión publicada `e67dc3de-e883-41ec-b93c-21c0459775df`: seguimiento con tres plantillas, dos días entre envíos y espera adicional de dos días. La comprobación de respuesta para marcar inactividad usa actividad del chat, no exclusivamente mensajes entrantes del cliente.
- `SAGFyESTLZLDdaNo`, versión publicada `4cb9c56a-acc9-45e7-b636-9ee0e0aa8929`: bot de recepción/localidad y derivación, con atención comercial humana posterior.

Limitaciones verificadas:

1. Atendidas cuenta conversaciones distintas por emisor humano y fecha del mensaje; asignadas cuenta conversaciones distintas por destinatario y fecha de asignación. No siguen necesariamente el mismo grupo de consultas. Un chat puede figurar en ambos vendedores y los totales por vendedor no son siempre sumables.
2. Los eventos de asignación guardan destinatario y fecha; no conservan explícitamente responsable anterior, actor y origen. El histórico comienza con ese registro, no con la instalación de Chatwoot.
3. Ventas del panel se atribuye al asignado actual y a la fecha del tagging. Una reasignación posterior puede mover una venta histórica de vendedor.
4. Hay una compra única por conversación, tanto por validación como por índice. El registro actual reutiliza esa compra y no admite una segunda compra independiente en el mismo chat.
5. El recordatorio editable de ventana fue retirado porque no tenía un emisor implementado. No se encontró un envío de 23–24 horas en los workflows v3 revisados. No se asumirá su existencia ni se generará un evento ficticio.
6. Una credencial llamada «bot» no demuestra por sí sola el tipo de emisor almacenado. Hay que distinguir automatizaciones explícitamente antes de considerar fiables las métricas humanas.

## Unidad de medición y registro comercial

Una **oportunidad** es una intención comercial identificable, vinculada con una conversación y un contacto. Un contacto puede tener varias conversaciones; una conversación puede contener varias oportunidades sucesivas. Mensajes y consultas no son unidades equivalentes.

- El primer entrante real de un cliente en una conversación comercial nueva inicia una oportunidad, sin duplicarla ante reintentos del webhook.
- Una conversación histórica sin oportunidad se incorpora mediante reconstrucción comprobable o como registro de cobertura parcial; un mensaje de soporte en un chat vendido no crea automáticamente otra oportunidad.
- Solo se admite una oportunidad comercial activa por conversación. El vendedor confirma «Nueva oportunidad» cuando corresponda; si ya hay una activa, se muestra la existente.
- «Registrar venta» confirma una venta por oportunidad. Dos clics, una reentrega de evento o volver a aplicar `vendido` no crean dos ventas.
- `vendido` continúa siendo una señal compatible con el trabajo actual. Si la etiqueta ya estaba puesta por una venta anterior, una segunda venta se confirma con la acción explícita sobre la nueva oportunidad, sin exigir quitar y volver a poner la etiqueta.
- Se conserva la venta anterior, su vendedor, fecha, producto y seguimiento. El resultado comercial no depende de que el estado nativo del chat sea `open` o `resolved`.
- «Perdida» requiere una acción explícita del vendedor y queda auditada. Cerrar un chat, agotar la secuencia o cerrar la ventana de WhatsApp no acredita una venta perdida.

Las pantallas utilizarán «consulta»; el detalle podrá mostrar que hay más de una oportunidad dentro de la misma conversación.

## Conteos, fechas y atribución

### Embudo de consultas ingresadas

El rango selecciona la fecha de inicio de las oportunidades, en `America/Argentina/Buenos_Aires`. Se muestra su situación al momento de consultar, con la indicación breve «Estado actual». Una consulta ingresada ayer y ganada hoy pertenece al embudo de ayer.

Cada oportunidad se cuenta una vez en el total y una vez en su situación comercial actual:

- En el bot.
- Sin asignar: requiere derivación y aún no tiene vendedor.
- Con vendedor, sin primera atención humana.
- En gestión: tuvo atención y no tiene resultado final.
- Ganada.
- Perdida.
- Cliente dejó de responder.

Los registros históricos que no puedan clasificarse con evidencia se muestran en «Sin información suficiente», con su cobertura identificada; no se reparten artificialmente entre los estados anteriores.

El gráfico de recorrido también muestra hitos alcanzados: derivación y atención. Esos hitos no se suman a los estados actuales como si fueran consultas adicionales. Una venta registrada sin respuesta humana comprobable se cuenta como ganada y se identifica como «Sin atención registrada»; no se inventa el hito de atención para completar el gráfico.

El filtro de vendedor aplica al responsable de la oportunidad activa; para ganadas y perdidas, al vendedor congelado al registrar el resultado. Si se filtra Juli o Marcos, las oportunidades sin responsable quedan fuera: no se mezclan totales globales con totales filtrados.

Se conservan asignado inicial, responsable efectivo, autores de respuestas y vendedor del resultado. Un traspaso cambia el responsable de la oportunidad activa, sin crear una consulta nueva ni trasladar una venta ya confirmada.

### Trabajo realizado en el período

Un bloque separado, «Actividad realizada», usa la fecha del evento: respuestas humanas, derivaciones y ventas ocurridas dentro del rango, aunque la consulta haya ingresado antes. Su gráfico y su tabla comparten filtros, métrica y listado.

«Consultas respondidas por vendedor» cuenta oportunidades distintas con respuesta de ese vendedor en el día o rango. Si dos vendedores responden la misma oportunidad, ambos tienen actividad, pero el total general se deduplica. No se presenta la suma de esas filas como cantidad de consultas únicas.

Los cierres diarios se agrupan en hora del negocio. Los porcentajes utilizan el mismo grupo de oportunidades y sus denominadores; un denominador vacío se muestra sin porcentaje. No se comparan asignadas de hoy con todas las respondidas hoy para calcular una tasa de atención.

## Atención humana y abandono

Una respuesta humana válida es un mensaje público saliente de un vendedor identificado, no fallido y no originado en una automatización. No cuentan notas privadas, actividades, saludos de derivación, plantillas automáticas ni mensajes de postventa. La entrega Meta es otra medición: registrar atención no demuestra lectura del cliente. Si después se informa un fallo de envío, se recalcula la atención pendiente.

Los mensajes automáticos nuevos llevarán origen y referencia de oportunidad. Se reutilizan los marcadores existentes de postventa. Para mensajes anteriores sin prueba de autoría se informa cobertura parcial, sin deducir humanidad únicamente del texto o del nombre de una credencial.

### Sin respuesta del vendedor

- Antes de la derivación, la consulta permanece en bot/sin asignar; no se atribuye incumplimiento a un vendedor que todavía no la recibió.
- El primer plazo comienza cuando requiere atención humana. Si el cliente escribe tras una respuesta humana o una automatización, se abre una nueva necesidad de atención.
- Mensajes consecutivos del cliente no postergan una atención ya pendiente. El reloj conserva la primera necesidad sin resolver.
- Se acumulan cuatro horas laborables. Base inicial coherente con el bot: lunes a sábado, 08:30–12:00 y 16:30–20:30. Fuera de esas franjas el reloj se pausa. No se inventa un calendario de feriados; las excepciones requerirán configuración explícita.
- Reasignar no reinicia el reloj ni borra el atraso. El detalle conserva los intervalos a cargo de cada vendedor.
- Un envío automático no resuelve la atención ni posterga el vencimiento. Una respuesta humana válida sí la resuelve.

«Sin respuesta del vendedor» es una incidencia de atención, no un resultado de venta. Puede aparecer en una consulta en gestión y no se suma como otra rama comercial. Una respuesta de postventa pendiente puede tener esta incidencia sin convertir una compra ganada en perdida.

### Cliente dejó de responder

- Requiere atención humana previa y que el turno pendiente sea del cliente. Si todavía se debe responder un entrante, la clasificación es atención pendiente del vendedor; las automatizaciones no transfieren esa responsabilidad al cliente.
- Se basa en mensajes entrantes reales posteriores al seguimiento, no en `last_activity_at` ni en notas o cambios de asignado.
- Se conserva la secuencia de tres pasos separados por dos días y la espera adicional de dos días que usa el circuito comercial actual; la espera se evalúa con su calendario, sin prometer exactamente 48 horas.
- La clasificación automática exige intentos identificados y válidos. Si el envío falla, corresponde una incidencia de envío, no imputar silencio al cliente. `sent` sin confirmación no se presenta como entrega probada.
- Los límites heredados de antigüedad no se convierten por sí solos en una venta perdida o abandono confirmado. Lo que no tenga evidencia suficiente queda sin clasificación fiable.
- Si el cliente responde, deja de estar inactivo y vuelve a atención humana en la misma oportunidad, sin duplicar el ingreso.

### Supuesto mensaje de 23–24 horas

Se auditarán las automatizaciones nativas y otras fuentes antes de utilizar esta señal. Si existe un envío, debe quedar identificado por mensaje, origen y momento. Si no existe, se muestra ausencia de registro; el alcance no incluye crear un recordatorio nuevo. La clasificación de atención pendiente funciona igualmente a partir del historial real.

## Reparto que contempla tomas manuales

Chatwoot será la fuente de verdad y efectuará selección y asignación en una operación transaccional; n8n pedirá derivar y utilizará el responsable devuelto para su presentación.

Regla inicial de diseño: priorizar al vendedor con menos oportunidades a cargo adquiridas en los últimos siete días corridos. Se toma el inicio del último tramo de responsabilidad efectiva, de modo que una toma manual de un chat antiguo también ingrese al cómputo. Se incluyen derivaciones automáticas, tomas manuales y traspasos. Una oportunidad aporta una unidad al responsable efectivo, no una unidad por cada evento de asignación. Las oportunidades finalizadas conservan el responsable del resultado durante esa ventana, para no borrar el trabajo al concretar una venta.

Ejemplo: Juli recibe diez consultas y Marcos recibe diez, pero Marcos toma otras cuatro de Juli. El reparto contabiliza seis para Juli y catorce para Marcos en ese conjunto; las próximas derivaciones favorecen a Juli. El historial conserva las veinte consultas y los cuatro traspasos.

- El empate usa un desempate persistente; solicitudes concurrentes no deben elegir usando el mismo conteo desactualizado.
- Se vuelve a comprobar bajo bloqueo que la conversación siga sin vendedor y sea derivable. Una toma manual concurrente se respeta.
- La clave idempotente de derivación se vincula con la oportunidad, no con toda la vida del chat. Un reintento devuelve el resultado existente sin repartir otra vez.
- Se conservan las protecciones de debounce/duplicados útiles del flujo actual. No habrá dos algoritmos de reparto activos para la misma derivación.
- El detalle muestra la ventana de siete días. Cambiarla no reescribe asignaciones anteriores ni significa repartir por cantidad de chats nativos abiertos.

## Compras, respuestas de postventa y recompra

Una venta confirmada se vincula con una oportunidad y con un registro independiente de compra. Se reemplaza la unicidad por conversación mediante una migración nueva; las referencias de compras, mensajes y etapas existentes se preservan.

El panel distingue:

1. Retomó contacto después de postventa: relación temporal con el intento identificado; no acredita que ese mensaje haya causado la consulta.
2. Nueva oportunidad confirmada por el vendedor.
3. Recompra ganada: nueva venta del mismo contacto con una compra anterior válida. Una conversación nueva del mismo contacto también puede contenerla.

Las consultas de garantía/soporte y agradecimientos continúan en su atención correspondiente y no incrementan las ventas. No se fusionan contactos por coincidencia aproximada de nombre o teléfono para fabricar recompras.

Coordinación propuesta para la misma conversación: una nueva oportunidad confirmada toma prioridad para atención humana. Las etapas de postventa anteriores aún no intentadas se interrumpen con motivo «Nueva oportunidad comercial»; no se cancela la venta anterior ni se borran envíos existentes. Las incidencias manuales anteriores permanecen visibles hasta su resolución. Al confirmar otra venta se crea su propia secuencia D+1/D+7/D+30. Esta regla evita automatismos simultáneos de la compra anterior y la nueva oportunidad.

La exclusión comercial actual por ID de conversación se sustituye por coordinación entre oportunidades y compras; no puede excluir permanentemente un chat por tener una compra histórica. Los contadores de seguimiento pertenecen a su oportunidad y los reintentos no reinician ni duplican la secuencia.

Para postventa se reutilizan los estados existentes, diferenciando fallido, no ejecutado y entrega no confirmada. Los números cuentan etapas, mientras que el embudo cuenta oportunidades; los enlaces conservan esos filtros y no comparan ambas unidades como si fueran iguales.

## Diseño de la pantalla

Una sola ruta de Actividad, manteniendo los accesos existentes a Seguimientos y Postventa:

1. Filtros por fecha/rango, vendedor y bandeja; selección en la URL y acción de limpiar.
2. Resumen compacto: ingresadas, pendientes de atención, en el bot y ganadas. Incidencias visibles con acceso al listado.
3. Recorrido gráfico con ramas de Juli/Marcos, pendientes, atención y resultado. Los hitos y estados actuales se distinguen visualmente; transferencias y datos incompletos son consultables. Una lista accesible ofrece los mismos datos del gráfico.
4. Actividad realizada: gráfico de evolución con selector de métrica y tabla por vendedor/día. Los valores abren un listado paginado; las agrupaciones semanales actuales se conservan.
5. Bloque breve de recompra y postventas que requieren intervención, enlazado con su detalle existente.

Se retiran del resumen y de la tabla «Mediana de primera respuesta» y «Ventanas cerradas sin respuesta». Mensajes enviados pasa a información secundaria; conversaciones abiertas/resueltas no expresa resultado comercial.

No se agregan párrafos bajo fecha, vendedor o bandeja. Las definiciones complejas se consultan mediante ayuda contextual, con textos cortos. Deben funcionar teclado, estados vacíos, carga/error y distribución móvil, respetando el tema visual de Chatwoot, i18n es/en y utilidades Tailwind.

## Límites técnicos y responsabilidades

- Registro comercial Arroyo: oportunidades y eventos propios con cuenta, conversación, contacto, origen, actor, fecha del hecho y clave de deduplicación. Proyecciones para el reporte sin consultar n8n en cada apertura del panel.
- Eventos de mensajes, asignaciones y etiquetas se capturan en Chatwoot. El contexto de actor/origen debe conservarse antes de perderlo en procesos asíncronos; no se reconstruye con `Current.user` dentro del job. Eventos repetidos o fuera de orden no duplican ni revierten indebidamente resultados.
- Servicios separados para atención/calendario, atribución/reparto, resultados/compras y consultas del panel. El mismo criterio alimenta tarjetas, gráficos, CSV y listados.
- n8n conserva recepción, coordinación y envío. La API Arroyo devuelve la asignación efectiva y las señales comerciales necesarias; se marcan saludos y seguimientos automáticos y se consulta la respuesta real del cliente.
- Nuevos registros y endpoints quedan en namespace Arroyo. Hooks core puntuales documentados en el plan de implementación y marcados `ARROYO:`. Se revisan extensiones Enterprise sin modificar sus archivos. No se editan migraciones anteriores ni se eliminan funciones nativas.
- Nuevas funciones detrás de flags por cuenta apagados por defecto: registro/embudo comercial y reparto con historial. El reparto no depende de que un usuario tenga abierto el panel. El panel actual continúa disponible mientras los nuevos flags estén apagados.
- Se conserva el contrato actual del panel durante la transición; el nuevo reporte usa un contrato propio/versionado y listados paginados. No se corta silenciosamente a 500 casos, ni se truncan elegibles de n8n.
- Las validaciones de permisos se aplican a toda la respuesta: embudo, bot, totales, listados y exportaciones. Un agente limitado a lo propio no obtiene totales globales o datos de otro vendedor manipulando filtros.

## Histórico y adopción

El registro comienza con los nuevos eventos y una reconstrucción controlada basada en mensajes, eventos de asignación y compras comprobables. Se distinguen cobertura completa y parcial; no se crea un ingreso histórico exacto, actor manual, vendedor de una venta o entrega Meta sin evidencia.

Una compra ya registrada conserva su vendedor original. Una etiqueta histórica `vendido` sin compra no desencadena automáticamente otra venta ni una secuencia retroactiva de mensajes. Los trabajos de reconstrucción no envían mensajes ni reasignan conversaciones.

La actualización se prepara con migraciones aditivas y contratos compatibles. Primero se despliega Chatwoot, luego se verifica con n8n sin habilitar el nuevo reparto; su publicación/activación se realiza después de pruebas locales y autorización de producción. Los flags permiten volver al panel anterior y al reparto anterior sin borrar el historial comercial generado. La revisión de una regresión no debe reactivar dos repartidores a la vez.

## Fases y criterios de aceptación

Orden funcional: (1) registro y métricas; (2) panel y gráficos; (3) atención pendiente; (4) reparto e inactividad en n8n; (5) recompra y coordinación de postventa. Las migraciones se diseñan desde el inicio para múltiples oportunidades/compras, aunque su acción de UI se habilite al final.

Casos mínimos de validación en local:

- Los estados actuales del mismo grupo suman el total; hitos y alertas no lo inflan. Una venta sin atención registrada no fabrica una respuesta humana.
- Una consulta ingresada ayer y atendida hoy conserva ambos días con sus criterios respectivos. La medianoche argentina no se agrupa en el día UTC.
- Saludo automático, nota privada y plantilla no cuentan como atención humana. Un fallo de respuesta no deja una consulta ficticiamente atendida.
- Dos vendedores pueden tener actividad sobre la misma consulta; el total único y los resultados no se duplican. Transferir después de la venta no mueve su vendedor histórico.
- Cuatro horas laborables respetan pausa del mediodía, noche y domingo. Mensajes adicionales, automatizaciones y transferencias no reinician el plazo.
- Tras la secuencia y espera, solo se clasifica silencio por evidencia pertinente; una nota o reasignación no simula una respuesta del cliente. Una respuesta real reactiva sin otro ingreso.
- Tomas manuales modifican el reparto siguiente. Derivaciones concurrentes, reintentos HTTP y toma manual durante una derivación respetan una asignación única.
- Dos compras en el mismo chat tienen referencias y etapas independientes. Una respuesta de garantía no crea una segunda oportunidad/venta. La nueva oportunidad no borra compra ni entrega anterior.
- Un usuario limitado a lo propio no puede consultar cifras o conversaciones ajenas por API, CSV o enlaces directos.
- Importación histórica, flags apagados y pruebas de fixtures no disparan mensajes. Comparar rendimiento con el panel actual usando el mismo volumen y rango antes de activar.

La implementación sigue [SALES_FUNNEL_IMPLEMENTATION.md](SALES_FUNNEL_IMPLEMENTATION.md). Este documento no publica workflows ni habilita nuevas reglas de producción.
