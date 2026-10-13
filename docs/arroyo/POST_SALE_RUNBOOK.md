# Postventa Arroyo: estado y puesta en marcha

Actualizado el 13 de octubre de 2026. Avance desarrollado en `arroyo/dev`, cuya publicación en GitHub fue solicitada por Mauro con las pruebas Rails pendientes ya informadas. Sin despliegue ni activación. Workflow n8n: [arroyo v3 · seguimientos post-venta](https://n8narroyo.thorque.com.ar/workflow/fF0LK453uWJdBHsR), carpeta Arroyo/v3.

`Staging` significa un entorno de pruebas separado de producción; no es una rama Git ni presupone que ya exista esa infraestructura. Las ramas remotas verificadas del fork son `arroyo/main` y `develop`; este avance se publica en `arroyo/dev`. No se crea una rama `staging`. Los pasos de prueba integrada de este documento requieren disponer de una instancia local o un entorno separado que ejecute `arroyo/dev`.

## Implementación preparada

Chatwoot registra una compra y sus tres etapas cuando se agrega `vendido` con postventa habilitada. Toma la fecha del evento y el vendedor asignado; permite corregir la fecha, guarda auditoría y conserva intentos anteriores. No importa conversaciones que ya tenían `vendido` ni crea otra compra al quitar y volver a aplicar la etiqueta. Actualmente se admite una compra por conversación.

n8n calcula los días de calendario D+1, D+7 y D+30 en `America/Argentina/Buenos_Aires`, a las 10:00 por defecto, y consulta cada 15 minutos. Hora, días, domingos y textos se leen desde la configuración de cuenta en Chatwoot. Registra el plan por revisión y solicita mensajes por una ruta Arroyo idempotente por etapa. Una corrección que deja etapas en el pasado genera tareas manuales; no provoca envíos acumulados.

Chatwoot distingue `queued`, `sent`, `delivered`, `read` y fallos. El ID del proveedor y la respuesta HTTP no acreditan entrega. Fuera de la ventana, sin plantilla válida, registra error `131047` y alerta; también observa errores posteriores de Meta. El supervisor corre cada 30 minutos y genera una tarea tras seis horas sin confirmación o sin ejecución. Una entrega tardía cierra una tarea pendiente, conservando las resoluciones manuales y el motivo original del fallo.

El panel Vendedores tiene una pestaña Postventa con etapas, contenido, estados, errores, fechas, vendedor, responsable y resolución por llamada, WhatsApp personal u otro medio. Administradores ven la cuenta; agentes ven sus compras o tareas asignadas. El historial sigue disponible al apagar postventa si el panel permanece habilitado. Las alertas son notas privadas con menciones nativas a los usuarios configurados, sin cambiar la asignación de la conversación.

La rama comercial anterior conserva su horario y lógica; ahora excluye las compras registradas en postventa habilitada y combina los atributos `seguimiento_*` mediante una ruta Arroyo, preservando otros atributos. Esto no convierte sus mensajes anteriores en seguimientos postventa trazables.

## Evidencia disponible

- 12 pruebas Node de planificación, paginación, ventana, plantillas, idempotencia y separación de ramas: aprobadas.
- 15 pruebas Vitest del panel y su pestaña: aprobadas. ESLint en los archivos JS/Vue/CJS tocados: aprobado.
- Análisis RuboCop independiente con las versiones del lockfile: aprobado; se excluyó `Layout/EndOfLine` por la diferencia LF/CRLF en Windows. No sustituye la validación con el bundle completo: queda pendiente junto con RSpec.
- Tres pruebas MCP en n8n con datos ficticios y todos los nodos HTTP simulados: registro de plan con contacto sin nombre; plan existente y plantilla aprobada fuera de ventana; flag apagado sin envío. Ejecuciones `606523`, `606547` y `606550`.
- Borrador guardado `329fddf0-da51-4850-9ec5-7216fdc4bf56`, 29 nodos. Versión publicada `f334bc60-3ddc-41a5-8b2e-4d69d6c321d2` y grafo publicado preservados; código de ambos nodos nuevos igual al del repositorio. Sin publicación ni ejecuciones contra clientes. Detalle en `n8n/post_sale-verification.json`.
- Segunda revisión independiente de código: sin nuevos hallazgos importantes; compatibilidad revisada con builder, factory, autenticación, menciones y listeners existentes.

Las pruebas Rails **no se ejecutaron**: Bundler informa `command not found: rspec`; la instalación del bundle quedó incompleta por dependencias nativas en Windows. La revisión de sintaxis/lint no confirma migraciones, callbacks, transacciones ni envío real. Tampoco hay validación visual con Rails funcionando. Estos puntos impiden considerar el cambio listo para producción.

## Verificación en un entorno Rails compatible

Usar Ruby de `.ruby-version` con rbenv y PostgreSQL/Redis del entorno de desarrollo, nunca una base de producción. Inicializar `eval "$(rbenv init -)"`, instalar el bundle y pnpm, y usar una base de prueba aislada. La migración nueva es `20261013120000_create_arroyo_post_sale_tracking.rb`; no se modificaron migraciones anteriores. Generar `db/schema.rb` con Rails después de migrar: permanece pendiente porque aquí no se pudo ejecutar Rails.

```bash
bundle install
pnpm install --frozen-lockfile
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:prepare
bundle exec rspec spec/services/arroyo/post_sale/message_service_spec.rb spec/controllers/api/v1/accounts/arroyo/post_sale_controller_spec.rb spec/controllers/api/v1/accounts/arroyo/features_controller_spec.rb spec/controllers/api/v1/accounts/arroyo/settings_controller_spec.rb spec/controllers/api/v1/accounts/arroyo/agent_panel_controller_spec.rb spec/models/arroyo/setting_spec.rb spec/builders/messages/message_builder_spec.rb spec/dispatchers/async_dispatcher_spec.rb spec/listeners/action_cable_listener_spec.rb spec/listeners/agent_bot_listener_spec.rb
bundle exec rubocop app/controllers/api/v1/accounts/arroyo app/services/arroyo/post_sale app/models/arroyo app/listeners/arroyo app/jobs/arroyo app/policies/arroyo app/dispatchers/sync_dispatcher.rb app/dispatchers/async_dispatcher.rb config/routes/arroyo.rb db/migrate/20261013120000_create_arroyo_post_sale_tracking.rb spec/services/arroyo/post_sale spec/controllers/api/v1/accounts/arroyo spec/models/arroyo
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/arroyo/panel/specs
node --test spec/javascript/arroyo/post_sale_n8n.test.cjs
```

Ejecutar también ESLint sobre el diff y los nuevos archivos JS/Vue/CJS. La publicación solicitada de este avance en la rama de desarrollo no acredita los checks Rails pendientes: deben completarse antes de integrar o desplegar. Verificar hooks y eventos core afectados al levantar web y Sidekiq. La migración debe estar aplicada antes de que el código nuevo atienda solicitudes, porque el endpoint de flags consulta la existencia de historial.

## Prueba funcional y activación

1. Desplegar primero en staging y migrar. Mantener `post_sale.enabled = false`; el flag viene apagado por defecto. Configurar el panel Vendedores y responsables de alertas: Julieta y Marcos deben ser usuarios de la cuenta y tener acceso a las bandejas WhatsApp participantes, o ser administradores.
2. Comprobar que la credencial existente `Chatwoot - admin` corresponde a un usuario administrador real de la cuenta objetivo. No basta su nombre. La API nueva requiere administrador para integración; el token de AgentBot no habilita estas rutas. Usar credenciales de staging para las pruebas integradas.
3. Las tres plantillas `postventa_d1`, `postventa_d7`, `postventa_d30` fueron creadas y enviadas a Meta el 13/10/2026. Al verificar, D+1 y D+7 figuraban activas; D+30 estaba en revisión. Ver textos, IDs y contraste con el flujo anterior en [META_POST_SALE_TEMPLATES.md](META_POST_SALE_TEMPLATES.md). Falta comprobar aprobación/sincronización en la bandeja Chatwoot y entrega real. El selector acepta plantillas sin variables o con parámetros `NAMED` conocidos; plantillas posicionales o con elementos no compatibles requieren adaptación antes de uso.
4. Preparar una conversación con un número propio. Habilitar postventa únicamente en la cuenta de prueba y agregar `vendido`. Comprobar fecha/vendedor, tres etapas y D+30 sin restricción geográfica. Corregir fecha y verificar auditoría, revisión y preservación de intentos; verificar etapas pasadas como tareas manuales.
5. Probar la ventana abierta y la cerrada con plantilla válida. Confirmar que dos solicitudes de la misma etapa crean un solo mensaje y que la etiqueta `seguimiento-manual` conserva otras etiquetas. Probar rechazo de Meta y observar `failed`, luego `delivered/read` desde el webhook real para demostrar la integración de estados.
6. Resolver una alerta como Julieta o Marcos. Confirmar autor, método y nota; probar entrega tardía y exclusión `no-contactar`, contacto bloqueado, `venta-cancelada` o retiro de `vendido`. El supervisor cierra tareas pendientes de una compra excluida.
7. Verificar permisos entre agentes y cuentas, historial al apagar la automatización y comportamiento nativo de Chatwoot. Verificar el merge de atributos del seguimiento comercial y que no contacte una compra ya registrada en postventa activa.
8. Con checks y staging aprobados, preparar el despliegue de producción y revisar el borrador final de n8n antes de publicarlo. Apuntar a la cuenta/bandeja correctas y habilitar postventa después de migrar. No publicar mientras faltan estas pruebas: el borrador utiliza rutas aún ausentes en producción y reemplaza la rama postventa anterior al publicarse.

## Qué significa comprobar las plantillas reales de Meta

Es verificar que la cuenta WhatsApp conectada a Arroyo tenga las plantillas correspondientes a los seguimientos, que Meta las haya aprobado y que los nombres, idioma y variables coincidan con la configuración. Los textos libres guardados en Chatwoot no crean una plantilla en Meta. `postventa_d1`, `postventa_d7` y `postventa_d30` fueron creadas con variables `asesor`/`producto`, idioma `es_AR` y categoría Marketing; el código debe leer su estado vigente después de la sincronización.

Después se prueba con un número propio para comprobar que el envío sea aceptado y se observe entrega desde el webhook real. Esta prueba no fue realizada; las pruebas MCP simularon las respuestas HTTP. Fuera de las 24 horas desde el último mensaje del cliente, WhatsApp Business Platform exige una plantilla aprobada ([política oficial](https://whatsappbusiness.com/policy/)). Si no hay una plantilla compatible o el envío falla, Chatwoot registra el caso y genera la tarea manual.

## Desactivación

Apagar `post_sale.enabled` impide nuevos planes/envíos y la consulta de compras devuelve una lista vacía; conserva historial y supervisión de seguimientos ya registrados. No elimina mensajes/tareas ni cancela mensajes que ya fueron encolados. La rama comercial sigue su lógica anterior si postventa está apagada.

No despublicar indiscriminadamente el workflow completo: también detendría el seguimiento comercial existente. Si hace falta volver al comportamiento anterior de n8n, restaurar su versión previa preservada en el historial y revisar/publicar ese cambio conscientemente. Conservar las tablas e historial de Chatwoot; evitar revertir la migración una vez que existan datos.
