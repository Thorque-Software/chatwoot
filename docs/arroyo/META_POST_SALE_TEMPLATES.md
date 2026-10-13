# Plantillas de postventa verificadas en Meta

Verificación y creación realizadas el 13/10/2026 en WhatsApp Manager, cuenta **Arroyo Fitness** (`1522924819426746`). Se enviaron plantillas a revisión de Meta, sin enviar mensajes a clientes ni activar la automatización.

## Plantillas nuevas

Categoría **Marketing**, idioma **Spanish (ARG) / es_AR**, parámetros **con nombre / NAMED**: `asesor` y `producto`. Sin encabezado, botones ni variables adicionales. Son compatibles con el selector del borrador n8n y los nombres por defecto de `Arroyo::Setting`.

| Etapa | Nombre | ID de Meta | Estado observado |
|---|---|---|---|
| D+1 | `postventa_d1` | `1082296844861303` | Activa: calidad pendiente |
| D+7 | `postventa_d7` | `2629718414108989` | Activa: calidad pendiente |
| D+30 | `postventa_d30` | `4662209877389097` | En revisión |

Los estados pueden cambiar después de esta verificación. La creación/aprobación no acredita entrega real: falta sincronizar y comprobar la metadata de la bandeja Chatwoot, y probar el envío con un número propio cuando el código nuevo esté funcionando.

### D+1

```text
¡Hola! Te escribe {{asesor}} de Arroyo Fitness 😊
Queríamos saber cómo te va con {{producto}} que compraste. Si tenés dudas sobre el uso, el armado o los cuidados, escribinos y te ayudamos.
También podemos recomendarte accesorios compatibles para aprovecharlo mejor. ¿Cómo viene?
```

Muestras para revisión: `asesor = Julieta`, `producto = la bicicleta que elegiste`.

### D+7

```text
¡Hola! Soy {{asesor}} de Arroyo Fitness 😊
Ya pasó una semana desde tu compra y queríamos saber cómo te está funcionando {{producto}}. ¿Pudiste usarlo como esperabas?
Si necesitás ayuda o querés conocer accesorios para complementarlo, respondé este mensaje y lo vemos juntos.
```

Muestras para revisión: `asesor = Marcos`, `producto = tu equipo de gimnasio`.

### D+30

```text
¡Hola! Soy {{asesor}} de Arroyo Fitness 😊
Ya pasó un mes desde tu compra y queríamos saber cómo viene {{producto}}. ¿Cómo fue tu experiencia hasta ahora?
Si tenés dudas sobre los cuidados o el mantenimiento, te ayudamos. También podemos recomendarte accesorios compatibles según el uso que le estés dando. ¿Lo vemos?
```

Muestras para revisión: `asesor = Julieta`, `producto = tu bicicleta`.

Las muestras no identifican clientes y no fijan los valores enviados: n8n obtiene el vendedor original y el producto registrado en la compra. Las tres plantillas sirven para bici o equipos de gimnasio mediante esa variable. No prometen un primer service obligatorio para todos los productos.

## Validación de las plantillas anteriores y su uso en n8n

Se leyó mediante MCP la versión **publicada** del workflow `fF0LK453uWJdBHsR`, versión `f334bc60-3ddc-41a5-8b2e-4d69d6c321d2`, y se comparó con las plantillas visibles en Meta.

| Uso anterior | Plantilla | Estado Meta observado | Configuración publicada de n8n |
|---|---|---|---|
| Accesorios bici | `arroyo_recompra_accesorios` | Activa, Marketing | `template_recompra`; desde D+1, hasta D+7 |
| Accesorios gym | `arroyo_recompra_accesorios_gym` | Activa, Marketing | `template_recompra_gym`; mismo plazo, etiqueta `aparatosgim` |
| Primer service bici | `arroyo_recordatorio_service` | Activa, Marketing | `template_service`; desde D+30, solo zona local, hasta D+75 |
| Seguimiento equipo gym | `arroyo_seguimiento_equipo_gym` | Activa, Utilidad | `template_service_gym` está vacío: seguimiento gym en pausa |

La plantilla gym del enlace aportado por Mauro, ID `1082157401402079`, está aprobada/activa en Meta y usa `customer_name` y `employee_name`. El campo vacío de n8n explica por qué su aprobación no basta para que el workflow la envíe. No se completó ese campo ni se modificó el workflow publicado.

La programación antigua toma `conversation.created_at` como fecha de compra, no el momento de aplicar `vendido`. No hay etapa D+7 en esa rama postventa. La rama comercial `seguimiento` tiene otra secuencia (`seg_dia_1`, `seg_dia_3`, `seg_dia_5`), que no constituye postventa de una compra.

Esta revisión confirma configuración y compatibilidad, no la entrega histórica de una compra concreta. Meta muestra estadísticas incompletas/intervalos seleccionados; no se inferió una entrega real a partir de esos contadores.

## Pendiente para puesta en marcha

1. Comprobar la aprobación de D+30 y la sincronización de las tres plantillas en la bandeja WhatsApp de Chatwoot.
2. Confirmar metadata `APPROVED`, idioma `es_AR`, `NAMED` y cuerpo con `asesor`/`producto` desde Chatwoot.
3. Completar las pruebas Rails/migración y el despliegue del código `arroyo/dev` en un entorno de pruebas separado.
4. Probar envío y webhook de entrega con un número propio antes de activar la secuencia. El workflow nuevo permanece en borrador.

[Panel de plantillas de Arroyo](https://business.facebook.com/latest/whatsapp_manager/message_templates/?business_id=183370558969611&tab=message-templates&nav_ref=whatsapp_manager&asset_id=1522924819426746).
