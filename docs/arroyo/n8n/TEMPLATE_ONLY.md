# Plantillas exclusivas — 20/10/2026

Estado: implementado en local sobre `arroyo/dev`. No desplegado ni publicado en n8n.

## Comportamiento

- Postventa: Chatwoot obtiene `postventa_d1`, `postventa_d7` o `postventa_d30` de la metadata sincronizada de Meta de la bandeja. Valida aprobación, idioma `es_AR`, componentes y variables `asesor`/`producto`; construye contenido y parámetros desde esa plantilla. La ventana abierta no habilita texto libre. El cuerpo o template enviados por un cliente antiguo se ignoran.
- Si la plantilla no está disponible o falta una variable, la etapa queda fallida con código local `template_unavailable` y tarea manual. No se atribuye ese fallo a un bloqueo de ventana de Meta. Las confirmaciones de entrega/lectura siguen viniendo del proveedor.
- Ajustes: solo muestra los nombres fijos de las plantillas; no permite editar mensajes ni elegir nombres distintos. Se oculta la configuración del recordatorio de 24 h, cuya ejecución no existe en esta rama. El panel de ventanas continúa disponible.
- Seguimiento comercial: mantiene los pasos `seg_dia_1`, `seg_dia_3`, `seg_dia_5`, cada dos días, sin recorte de conversaciones. El texto mostrado y los parámetros NAMED se obtienen de la metadata de Meta incluida en `GET purchases`, aun si no hay compras. Si una plantilla requerida no es válida, el clasificador falla antes de iniciar los envíos: la incidencia queda en la ejecución de n8n; no existe una nueva tarea manual comercial.

## Parche para el workflow publicado

`template-only-operations.json` cambia únicamente cuatro parámetros de nodos existentes. No reemplaza el workflow ni toca triggers, credenciales o conexiones. Fue preparado contra la versión publicada `2f62b138-d150-48e7-885f-4d47b1381e9a`. Antes de aplicarlo, comprobar que esa versión siga vigente; si cambió, regenerar con `buildTemplateOperations(workflow)` en `template-only-build.cjs` y revisar diferencias.

El generador histórico `post_sale-build.cjs` también incluye el nuevo comportamiento y las correcciones comerciales de 19/10. Sus operaciones completas no se deben aplicar de nuevo sobre el workflow existente.

## Orden de publicación

1. Desplegar esta versión de Chatwoot y verificar que WhatsApp tenga las seis plantillas aprobadas sincronizadas.
2. Comprobar que `GET purchases` incluya `config.commercial_templates` y que la configuración visible no tenga cuerpos editables.
3. Aplicar y publicar el parche incremental de cuatro nodos en n8n. No ejecutar manualmente toda la rama comercial como prueba.
4. Verificar una etapa de postventa debida con un número autorizado y observar confirmación de entrega.

Compatibilidad durante el paso 1: `GET purchases` entrega `free_text: ""` únicamente como campo transitorio para que la versión anterior de n8n no falle al preparar la petición. No es editable, no se usa como mensaje y no se expone en Ajustes. Chatwoot resuelve siempre la plantilla del lado servidor. El nuevo n8n solo envía revisión e identificador de ejecución para postventa.

Pruebas locales: Node ejecuta el código generado con fixtures, incluidos 400 destinatarios y cadencia de dos días; Rails valida idempotencia, plantilla dentro/fuera de ventana y alerta sin plantilla; Vitest valida la eliminación de editores y el panel existente. Las pruebas no envían WhatsApp reales.
