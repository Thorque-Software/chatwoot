# Adaptación al mock-up aprobado — 20/10/2026

Autorización: «Me parece perfecto ese diseño. Quiero que entonces adaptes el panel de vendedores y la información actual a ese estilo». Referencia: `design-plans/arroyo-actividad/mockup-{desktop,mobile}.png` y su README. Trabajo local en `arroyo/dev`, sin publicar ni commitear.

## Contratos y decisiones

- Reutilizar reporte v2, permisos, filtros URL, listados, CSV y acciones de oportunidades. No tocar backend ni n8n.
- Resumen de cuatro cifras, alerta contextual, recorrido conectado a vendedores dinámicos y actividad con gráfico/tabla agrupados; postventa secundaria.
- El nodo histórico se llama «Derivadas», no «Con vendedor»: `assigned` mide el hito y puede incluir una consulta luego desasignada. La ayuda conserva esta distinción.
- No inventar totales por vendedor sumando días: una consulta puede aparecer en varios días. El total general de actividad conserva su deduplicación del servidor.
- Mantener todos los estados consultables en un desplegable discreto. Cobertura parcial y datos desconocidos siguen visibles cuando corresponda.
- Filtros compactos solo con el nuevo embudo; resto de pantallas y panel legado conservan su composición. No editar primitivas core ni Enterprise.
- CSS exclusivamente Tailwind, i18n es/en, reutilizar Select/MultiSelect/Popover/BarChart/Button. Sin animaciones de entrada ni librerías nuevas.

## Ejecución

1. [x] Pruebas RED: ramas/vendedores dinámicos, origen y resultado separados, gráfico por vendedor y filtro de su barra, tabla móvil desplegable, incidencias/ceros.
2. [x] Adaptar CohortFlow y FunnelTab; conservar listados, permisos, CSV, errores y agrupación semanal.
3. [x] Compactar PanelFilters mediante variante local; integrar encabezado/exportación y traducciones. Probar flag apagado y otras pestañas.
4. [x] Vitest/ESLint, sincronización del runtime local y revisión final. La prueba visual queda pendiente por la restricción del navegador local de Work.

Antes de concluir: comparar contra el mock-up y comprobar que no existen nombres, números ni vendedores de demostración hardcodeados en el producto.

## Resultado y verificación

- Adaptación implementada en local: filtros compactos, cuatro indicadores, aviso de consultas desatendidas, recorrido conectado con vendedores reales, evolución por vendedor y tabla de actividad, resumen secundario de postventa.
- Los estados completos se consultan mediante un desplegable y las explicaciones se muestran en ayudas contextuales. La tabla se puede desplegar en móvil.
- Revisión independiente: corregidas la confusión entre ausencia de consultas nuevas y ausencia de actividad, y la explicación de cada métrica según su evento real. Ambas regresiones se reprodujeron antes de corregirse.
- Vitest: 55 pruebas aprobadas en seis archivos. ESLint: nueve archivos sin errores ni advertencias. Tailwind: compilación satisfactoria. `git diff --check`: sin errores.
- Los ocho archivos de ejecución del frontend coinciden por SHA256 con el contenedor local. `http://localhost:3300/app/login` responde HTTP 200.
- La comparación de estructura con el mock-up se realizó sobre las fuentes; no se pudo completar la inspección visual en navegador porque Work tiene deshabilitado el acceso al navegador local. No se afirma validación visual en vivo.
- Sin cambios de backend o n8n en esta adaptación. Sin commit, push ni publicación en producción.
