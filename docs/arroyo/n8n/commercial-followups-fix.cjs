// Correcciones comerciales aplicables al workflow publicado y al generador.
function correctClassifier(code) {
  if (code.includes('const DIAS_ENTRE_ENVIOS = 2;')) return code;
  if (
    !code.includes('// ROTACION JUSTA.') ||
    !code.includes('  const asignado = norm(')
  )
    throw new Error(
      'Commercial classifier changed: review before applying corrections'
    );
  const cadence = [
    '  // ARROYO: dos días calendario entre mensajes; el cron sigue siendo diario.',
    '  // No recuperar todos los pasos atrasados ni adivinar fechas faltantes.',
    '  const DIAS_ENTRE_ENVIOS = 2;',
    "  const diaAnterior = Date.parse(ultimoEnvio + 'T00:00:00Z');",
    "  const diasDesdeEnvio = (Date.parse(HOY + 'T00:00:00Z') - diaAnterior) / 86400000;",
    '  if (enviados > 0 && (!Number.isFinite(diasDesdeEnvio) || diasDesdeEnvio < DIAS_ENTRE_ENVIOS)) continue;',
    '',
  ].join('\n');
  const updated = code
    .replace(
      /const MAX = Number\(cfg\.max_seguimiento_por_corrida \?\? 40\);\n/,
      ''
    )
    .replace(
      '  const asignado = norm(',
      cadence + '\n  const asignado = norm('
    );
  return (
    updated.slice(0, updated.indexOf('// ROTACION JUSTA.')) +
    '// ARROYO: procesar todos los elegibles, uno por vez en el bucle de envío.\n' +
    'salida.sort((a, b) => String(a.json.ultimo_envio_previo).localeCompare(String(b.json.ultimo_envio_previo)));\n' +
    "console.log('Conversaciones evaluadas: ' + vistos.size + ' | acciones elegibles: ' + salida.length + ' | ya enviadas hoy: ' + yaHoy + ' | sin vendedor: ' + sinVendedor);\n" +
    'return salida;'
  );
}
function buildCorrections(classifier, assignments) {
  const set = (nodeName, path, value) => ({
    type: 'setNodeParameter',
    nodeName,
    path,
    value,
  });
  return [
    set(
      'Clasificar Seguimiento Diario',
      '/jsCode',
      correctClassifier(classifier)
    ),
    set(
      'Config Chatwoot',
      '/assignments/assignments',
      assignments.filter(item => item.name !== 'max_seguimiento_por_corrida')
    ),
    set(
      'Buscar Chats con Seguimiento',
      '/jsonBody',
      "={{ JSON.stringify({ payload: [ { attribute_key: 'labels', filter_operator: 'equal_to', values: [$('Config Chatwoot').first().json.label_seguimiento] } ] }) }}"
    ),
    set(
      'Hoy Se Manda?',
      '/conditions/conditions/0/leftValue',
      "={{ !String($('Config Chatwoot').first().json.dias_sin_envio || '').split(',').map((s) => Number(String(s).trim())).includes($now.setZone('America/Argentina/Buenos_Aires').weekday) }}"
    ),
    set(
      'Buscar Chats con Seguimiento',
      '/options/pagination/pagination/limitPagesFetched',
      false
    ),
    set(
      'Buscar Chats con Seguimiento',
      '/options/pagination/pagination/paginationMode',
      'updateAParameterInEachRequest'
    ),
    set(
      'Buscar Chats con Seguimiento',
      '/options/pagination/pagination/parameters/parameters',
      [{ type: 'qs', name: 'page', value: '={{ $pageCount + 1 }}' }]
    ),
  ];
}
module.exports = { buildCorrections, correctClassifier };
