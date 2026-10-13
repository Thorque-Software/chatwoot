const fs = require('node:fs');
const path = require('node:path');

function buildOperations(baseline) {
  const helpers = fs
    .readFileSync(path.join(__dirname, 'post_sale-transform.cjs'), 'utf8')
    .split('module.exports =')[0];
  const baseUrl =
    "$('Config Postventa').first().json.url_chatwoot.replace(/\\/$/, '') + '/api/v1/accounts/' + $('Config Postventa').first().json.account_number";
  const postSaleUrl = baseUrl + " + '/arroyo/post_sale'";
  const credentials = {
    httpHeaderAuth: { id: 'zI1K6Ff66q6QgBnj', name: 'Chatwoot - admin' },
  };
  const codeNode = (name, jsCode, position) => ({
    name,
    type: 'n8n-nodes-base.code',
    typeVersion: 2,
    position,
    parameters: { mode: 'runOnceForAllItems', jsCode },
  });
  const httpNode = (name, method, url, jsonBody, position) => ({
    name,
    type: 'n8n-nodes-base.httpRequest',
    typeVersion: 4.2,
    position,
    credentials,
    parameters: {
      method,
      url: '={{ ' + url + ' }}',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      ...(jsonBody ? { sendBody: true, specifyBody: 'json', jsonBody } : {}),
      options: {
        response: { response: { responseFormat: 'json' } },
        timeout: 30000,
      },
    },
  });
  const readPurchases = httpNode(
    'Leer Compras Postventa',
    'GET',
    postSaleUrl + " + '/purchases'",
    null,
    [-336, -144]
  );
  readPurchases.parameters.options.pagination = {
    pagination: {
      paginationMode: 'updateAParameterInEachRequest',
      parameters: {
        parameters: [
          { type: 'qs', name: 'page', value: '={{ $pageCount + 1 }}' },
        ],
      },
      paginationCompleteWhen: 'other',
      completeExpression: '={{ $response.body.meta.next_page === null }}',
      requestInterval: 150,
    },
  };
  const pollPostSale = {
    name: 'Postventa Cada 15 Minutos',
    type: 'n8n-nodes-base.scheduleTrigger',
    typeVersion: 1.3,
    position: [-784, -144],
    parameters: {
      rule: {
        interval: [{ field: 'cronExpression', expression: '0 */15 * * * *' }],
      },
    },
  };
  const configPostSale = {
    name: 'Config Postventa',
    type: 'n8n-nodes-base.set',
    typeVersion: 3.4,
    position: [-560, -144],
    parameters: {
      mode: 'manual',
      assignments: {
        assignments: [
          {
            id: 'url-postsale',
            name: 'url_chatwoot',
            type: 'string',
            value: 'https://chatarroyo.thorque.com.ar/',
          },
          {
            id: 'account-postsale',
            name: 'account_number',
            type: 'string',
            value: '1',
          },
        ],
      },
      options: {},
    },
  };
  const coordination = JSON.parse(JSON.stringify(readPurchases));
  coordination.name = 'Compras para Coordinacion Comercial';
  coordination.position = [-336, 336];
  coordination.parameters.url = coordination.parameters.url.replaceAll(
    'Config Postventa',
    'Config Chatwoot'
  );
  const preparePurchases = codeNode(
    'Preparar Compras Postventa',
    helpers +
      '\nreturn purchaseItems($input.all().map(item => item.json)).map(({purchase, config}) => ({json: {purchase, needs_plan: purchase.revision !== purchase.planned_revision, plan: planPurchase(purchase, config)}}));',
    [-112, -144]
  );
  const requiresPlan = {
    name: 'Requiere Plan Postventa?',
    type: 'n8n-nodes-base.if',
    typeVersion: 2.2,
    position: [112, -144],
    parameters: {
      conditions: {
        options: {
          caseSensitive: true,
          leftValue: '',
          typeValidation: 'strict',
          version: 2,
        },
        conditions: [
          {
            id: 'needs-plan',
            leftValue: '={{ $json.needs_plan }}',
            rightValue: '',
            operator: { type: 'boolean', operation: 'true', singleValue: true },
          },
        ],
        combinator: 'and',
      },
      options: {},
    },
  };
  const registerPlan = httpNode(
    'Registrar Plan Postventa',
    'PUT',
    postSaleUrl +
      " + '/purchases/' + encodeURIComponent($json.purchase.reference) + '/plan'",
    '={{ JSON.stringify($json.plan) }}',
    [336, -240]
  );
  const selectStages = codeNode(
    'Seleccionar Etapas Postventa',
    helpers +
      "\nconst config = $('Leer Compras Postventa').first().json.config;\nconst seen = new Set();\nreturn $input.all().flatMap(item => {\n  if (item.json.error) return [];\n  const purchase = item.json.purchase || item.json;\n  return dueMessages(purchase, config, $now.toISO(), String($execution.id)).filter(message => {\n    if (seen.has(message.id)) return false;\n    seen.add(message.id);\n    return true;\n  }).map(message => ({json: message}));\n});",
    [560, -96]
  );
  const createMessage = httpNode(
    'Crear Mensaje Postventa',
    'POST',
    postSaleUrl + " + '/follow_ups/' + $json.id + '/message'",
    '={{ JSON.stringify($json.body) }}',
    [784, -96]
  );
  createMessage.notes =
    'Única ruta de envío postventa. La respuesta queued/sent no demuestra delivered/read. Timeout: repetir esta ruta idempotente, nunca POST nativo. Plantillas verificadas desde metadata sanitizada de la compra.';
  const nodes = [
    pollPostSale,
    configPostSale,
    readPurchases,
    preparePurchases,
    requiresPlan,
    registerPlan,
    selectStages,
    createMessage,
    coordination,
    {
      name: 'Postventa Arroyo Borrador',
      type: 'n8n-nodes-base.stickyNote',
      typeVersion: 1,
      position: [-784, -752],
      parameters: {
        content:
          '## BORRADOR · Postventa Arroyo D1/D7/D30\n\nNo publicar antes de deploy y prueba con número propio. Postventa consulta cada 15 minutos; hora, zona, días, domingos, textos y nombres de plantilla salen de GET purchases. Fecha de compra y vendedor los registra Chatwoot al aplicar vendido.\n\nEl único POST saliente de postventa es /arroyo/post_sale/follow_ups/:id/message (idempotente por etapa/revisión). queued/sent NO significa entregado. Plantilla solo si metadata APPROVED y parámetros conocidos; sin plantilla válida fuera de ventana el backend registra fallo y tarea manual. Etapas atrasadas más que el plazo declarado quedan para watchdog/manual.\n\nFlag apagado por defecto. No importar vendido histórico. Rama comercial conserva cron10; lee compras vigentes para evitar contacto simultáneo y mergea solo seguimiento_* por ruta Arroyo. Credencial Chatwoot - admin descubierta; verificar usuario/rol real en staging.',
        width: 1240,
        height: 512,
        color: 4,
      },
    },
  ];
  const operations = baseline.removeNodes.map(nodeName => ({
    type: 'removeNode',
    nodeName,
  }));
  operations.push({
    type: 'removeConnection',
    source: 'Config Chatwoot',
    target: 'Hoy Se Manda?',
  });
  operations.push(...nodes.map(node => ({ type: 'addNode', node })));
  const links = [
    ['Postventa Cada 15 Minutos', 'Config Postventa'],
    ['Config Postventa', 'Leer Compras Postventa'],
    ['Config Chatwoot', 'Compras para Coordinacion Comercial'],
    ['Compras para Coordinacion Comercial', 'Hoy Se Manda?'],
    ['Leer Compras Postventa', 'Preparar Compras Postventa'],
    ['Preparar Compras Postventa', 'Requiere Plan Postventa?'],
    ['Requiere Plan Postventa?', 'Registrar Plan Postventa', 0],
    ['Requiere Plan Postventa?', 'Seleccionar Etapas Postventa', 1],
    ['Registrar Plan Postventa', 'Seleccionar Etapas Postventa'],
    ['Seleccionar Etapas Postventa', 'Crear Mensaje Postventa'],
  ];
  operations.push(
    ...links.map(([source, target, sourceIndex = 0]) => ({
      type: 'addConnection',
      source,
      target,
      sourceIndex,
    }))
  );
  [registerPlan, createMessage].forEach(node =>
    operations.push({
      type: 'setNodeSettings',
      nodeName: node.name,
      settings: { onError: 'continueRegularOutput', retryOnFail: false },
    })
  );
  const commercialGuard =
    helpers +
    "\nconst activePostSaleConversations = new Set(activeConversationIds($('Compras para Coordinacion Comercial').all().map(item => item.json)));\n";
  const commercialCode =
    commercialGuard +
    baseline.commercialClassifier.replace(
      'for (const c of convs) {',
      'for (const c of convs) {\n  // ARROYO: nueva compra registrada evita contacto comercial simultáneo.\n  if (activePostSaleConversations.has(String(c.id))) continue;'
    );
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Clasificar Seguimiento Diario',
    path: '/jsCode',
    value: commercialCode,
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Config Chatwoot',
    path: '/assignments/assignments',
    value: baseline.commercialAssignments,
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Sticky Modo Prueba',
    path: '/content',
    value:
      '## Prueba comercial\n\nsolo_conversaciones en Config Chatwoot limita únicamente la rama comercial. Vacío permite todos los chats elegibles. Postventa se prueba en staging con cuenta/número propio y flag controlado; no ejecutar este borrador contra clientes. No publicar hasta verificar backend, rol admin y plantillas D1/D7/D30.',
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Sticky Se Mando',
    path: '/content',
    value:
      'Rama comercial heredada: id confirma creación de mensaje, NO entrega Meta. Se conservan sus reglas. Los contadores seguimiento_* se guardan por merge atómico Arroyo. Postventa registra estados/errores aparte y no usa estos marcadores como prueba de entrega. Pendiente verificar sender real de la credencial comercial en staging.',
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Sticky Seguimiento Diario',
    path: '/content',
    value:
      '## Seguimiento comercial diario\n\nSe conservan cron10, lunes a sábado, secuencia por número de envío seg_dia_1/seg_dia_3/seg_dia_5, vendedores Juli/Marcos, espera de cierre y límites de antigüedad. GET purchases excluye compras nuevas vigentes de postventa; ninguna venta histórica se reclasifica.\n\nConfig Chatwoot contiene solo configuración comercial. Postventa tiene trigger cada15 y configuración efectiva desde Rails. Marcar Envio Del Dia/Resetear Contador usan ruta Arroyo con lock para preservar atributos ajenos. Las etiquetas conservan el set ajeno ya leído por el clasificador comercial.',
  });
  baseline.attributeNodes.forEach(node => {
    operations.push({
      type: 'setNodeParameter',
      nodeName: node.name,
      path: '/url',
      value:
        '={{ ' +
        postSaleUrl.replaceAll('Config Postventa', 'Config Chatwoot') +
        " + '/conversations/' + $('Armar Seguimiento').item.json.conversation_id + '/attributes' }}",
    });
    operations.push({
      type: 'setNodeCredential',
      nodeName: node.name,
      credentialKey: 'httpHeaderAuth',
      credentialId: credentials.httpHeaderAuth.id,
      credentialName: credentials.httpHeaderAuth.name,
    });
    operations.push({
      type: 'setNodeSettings',
      nodeName: node.name,
      settings: { onError: 'stopWorkflow' },
    });
  });
  return { workflowId: baseline.workflowId, operations };
}

if (require.main === module) {
  const baseline = JSON.parse(
    fs.readFileSync(path.join(__dirname, 'post_sale-baseline.json'), 'utf8')
  );
  fs.writeFileSync(
    path.join(__dirname, 'post_sale-operations.json'),
    JSON.stringify(buildOperations(baseline), null, 2) + '\n'
  );
}

module.exports = { buildOperations };
