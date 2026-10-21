# Propuesta visual — Actividad comercial Arroyo

Fecha: 20/10/2026. Escrita contra `f26c3e6c14` más la implementación local sin commit de oportunidades comerciales.

## Entrega

- `mockup-desktop.png` / `.svg`: escritorio de 1440 × 1152 unidades.
- `mockup-mobile.png` / `.svg`: móvil de 390 × 1720 unidades.
- Los PNG se exportan al doble de resolución. Son mock-ups estáticos, no capturas del navegador ni pantallas publicadas. Botones, filtros, tooltip de ayuda y enlaces representan posiciones y estados; no ejecutan acciones.
- Datos de los once casos sintéticos preparados para la evaluación local. Ningún número pretende representar producción. No hay importes, variaciones porcentuales inventadas ni integración contable.

## Design language

- **Audited surface:** Panel de vendedores → Actividad, `/app/accounts/1/arroyo/panel`, con `agent_panel.funnel_enabled`. Incluye encabezado/filtros, `FunnelTab` y `CohortFlow`. El sidebar solo se representa como contexto; no se propone cambiarlo.
- **Design sources:** `AGENTS.md`; diseño aprobado `docs/arroyo/SALES_FUNNEL_DESIGN.md:148–160`; colores existentes `app/javascript/dashboard/assets/scss/_next-colors.scss`; `theme/colors.js` y `tailwind.config.js`.
- **Documented decisions:** resumen compacto; distinción entre ingreso e hitos; gráfico por vendedor; evolución y tabla diaria; ayudas contextuales sin párrafos bajo filtros; conservar accesos de Seguimientos y Postventa. Facturación excluida.
- **Governing owners and consumers:** `panel/Index.vue` compone `PanelFilters.vue` y, bajo el flag, `FunnelTab.vue`; este importa `CohortFlow.vue`, `OpportunitiesDrawer.vue` y el `BarChart.vue` compartido. Los componentes usan `n-*`, resueltos en `theme/colors.js` a variables de `_next-colors.scss`. La tipografía se hereda de `_woot.scss`, que importa esos colores y las fuentes Inter; el artefacto vectorial usa Segoe UI, fallback existente de `tailwind.config.js`, para exportar texto de forma reproducible.
- **Explicit exceptions:** None documented.

## Findings

No supported findings were found.

No se afirma que el producto renderizado tenga un defecto específico de jerarquía, densidad, interacción o contraste. La inspección del navegador está deshabilitada en Work. El código demuestra la composición, las etiquetas y los propietarios, pero no permite certificar su presentación actual. La solicitud del usuario autoriza explorar otra distribución; esta entrega es una propuesta, no un diagnóstico visual probado.

## Improve first

No supported recommendation.

Como **hipótesis de diseño solicitada**, el primer cambio que se propone evaluar es expresar el recorrido como un diagrama conectado hacia cada vendedor. Su aceptación debe evaluarse viendo los mock-ups y luego el producto, sin atribuirle mejoras de usabilidad medidas que todavía no existen.

## Decisión visual propuesta

1. **Resumen.** Cuatro cifras reconocibles: ingresadas, sin primera atención, bot y ganadas. El color de ganadas es teal; los atrasos se identifican con amber. La alerta de atención ocupa una franja con una acción concreta, sin convertirse en otro bloque de métricas.
2. **Recorrido.** Un ingreso de once consultas se divide en una en bot, una sin asignar y nueve con vendedor. Estas últimas se distribuyen entre cinco de Julieta y cuatro de Marcos. Cada rama muestra su atención y resultado sin fabricar atención humana para completar una venta. La ayuda sobre hitos/estados queda asociada al título del diagrama.
3. **Evolución.** Un solo bloque contiene selector de métrica, barras agrupadas por vendedor y tabla diaria. Sustituye la repetición de una tabla grande de estado actual que el diagrama ya comunica. Las agrupaciones actuales por día/semana deben conservarse al implementarlo.
4. **Postventa.** Un bloque secundario presenta recompra, regreso del cliente e incidencias, con acceso al detalle existente. La cifra de incidencias cuenta consultas, no mensajes ni etapas D+1/D+7/D+30.
5. **Móvil.** El recorrido se apila y los vendedores conservan sus resultados. La tabla diaria se abre desde «Ver detalle por vendedor y día» en la misma vista; no implica ir conversación por conversación. Ese desplegable está propuesto, no implementado. Los filtros ocupan dos filas, con el inbox como chip.

No se proponen otras reglas de conteo, asignación, venta, postventa o permisos. «Sin primera atención» y «Sin respuesta del vendedor» se conservan como conceptos distintos: la primera es un estado; la segunda es un atraso que también puede existir tras atención previa. «Cliente sin respuesta» identifica la clasificación de inactividad del cliente.

## Reuse y alcance de una implementación posterior

- **Propietario de distribución:** `app/javascript/dashboard/routes/dashboard/arroyo/panel/Index.vue`. Reordenar el encabezado y mantener la URL de filtros y el flag actual.
- **Filtros:** reutilizar `PanelFilters.vue`, `components-next/select/Select.vue` y `components-next/filter/inputs/MultiSelect.vue`. El mock-up propone una composición compacta, no otro motor de filtrado.
- **Recorrido:** modificar `CohortFlow.vue`, manteniendo `drillDown` y el contrato del reporte. Mostrar «Sin información suficiente» cuando haya registros parciales; si cambia el filtro de vendedor, no mantener ramas o totales globales ajenos a ese filtro. Ceros, vendedores adicionales y nombres largos deben conservar espacio legible.
- **Indicadores/actividad:** `FunnelTab.vue`; reutilizar `shared/components/charts/BarChart.vue`, `commercialConstants.js` y `OpportunitiesDrawer.vue`. Conservar respuestas asincrónicas, CSV, paginación, acciones y permisos.
- **Identidad:** reutilizar `n-solid-2`, `n-slate-11/12`, `n-blue-9/11`, `n-teal-11`, `n-amber-11`, `n-ruby-11`, los tamaños tipográficos existentes y la familia Lucide. No crear un sistema paralelo de componentes.
- **Textos finales:** traducciones es/en en `app/javascript/dashboard/i18n/locale/{es,en}/arroyo.json`. Los textos incrustados en los SVG son contenido de presentación del mock-up, no i18n de producto.
- **Exclude:** sidebar real, Postventa/Seguimientos internos, backend, migraciones, reglas n8n, permisos y Enterprise. No hay cambios de producto, documentación de producto, dependencias instaladas, commits ni publicaciones en esta entrega.

## Better UI — superficies, iconos y movimiento

El artefacto usa los valores de tema oscuro existentes, radios de superficie de 12, controles de 8 y una sola biblioteca de iconos. Se conservan divisores estructurales y límites de campos; las superficies elevadas usan un borde visual blanco de 8 % en oscuro, sin sombra grande. Las tarjetas internas se tratan como superficies independientes cuando los márgenes son asimétricos.

### Hallazgos de polish del artefacto

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `generate-mockup.cjs:94`, variante de 171 px | Icono y etiqueta larga competían por el mismo espacio en la primera exportación móvil. | Omitir los iconos decorativos en las tarjetas móviles; conservar título y cifra. | Alineación óptica: evita superposición y conserva la lectura del indicador. |

La corrección está incorporada al mock-up. No quedan hallazgos HIGH de polish en los estados estáticos inspeccionados. **Approve** se limita a esos dos artefactos estáticos; no aprueba el producto ni la interacción no inspeccionada.

Para la implementación posterior: usar el botón nativo; si se añade feedback de presión, `0.96`, `150ms`, `ease-out`, solo habilitado y bajo `prefers-reduced-motion: no-preference`. Tabs y hover de filas deben ser instantáneos o cambios de fondo/opacidad de hasta 150 ms. Hover solo con puntero compatible; overlays con `overscroll-behavior: contain`. No se diseña entrada escalonada para una vista de trabajo frecuente. No usar `transition-all` ni keyframes para apertura/cierre.

## Validación y límites

- **Inspeccionado:** exportaciones desktop/móvil mediante visor de imágenes; texto, límites, conexiones y sumas del escenario de demostración. Se corrigieron iconos que se superponían y la etiqueta de falta de respuesta del cliente.
- **Datos:** estados actuales `bot 1 + sin asignar 1 + pendiente 1 + gestión 2 + ganadas 4 + perdidas 1 + cliente inactivo 1 = 11`. Derivadas 9 y atendidas 7 son hitos; no se suman a esos estados. Julieta tiene tres respuestas diarias en el rango y Marcos cuatro. Una oportunidad ganada no tiene atención humana registrada.
- **Not verified:** aplicación actual renderizada; teclado, focus, touch/hover, popovers, dark/light toggle y reduced motion en el navegador; nombres largos, errores, carga, vacío y más de dos vendedores en un producto implementado. Los SVG no reproducen interacciones.
- **Stop conditions:** no implementar sin aceptación del mock-up; si los permisos, el contrato o las unidades reales difieren, mantener esas reglas y revisar la propuesta. No inferir nuevas métricas de un dibujo.
- **Documentación posterior:** si se acepta e implementa, registrar la composición final en `docs/arroyo/SALES_FUNNEL_DESIGN.md`; ese archivo no se modifica durante esta exploración.

Regeneración, sin instalar paquetes: `node design-plans/arroyo-actividad/generate-mockup.cjs`. Usa Sharp ya incluido en el runtime local y los iconos/colores existentes del repositorio. Solo escribe los SVG y PNG de esta carpeta.
