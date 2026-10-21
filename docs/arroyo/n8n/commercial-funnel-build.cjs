const fs = require('node:fs');
const path = require('node:path');

// Embedded verbatim into the Code node; all network calls use HTTP Request nodes.
function classifyCommercial(
  conversations,
  pages,
  cfg,
  templateConfig,
  now,
  renderTemplate
) {
  const contexts = new Map(
    pages
      .flatMap(page => page.contexts)
      .map(c => [String(c.conversation_id), c])
  );
  const seen = new Set();
  const output = [];
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Argentina/Buenos_Aires',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(now));
  const norm = value =>
    String(value || '')
      .toLowerCase()
      .trim();
  const aliases = value =>
    String(value || '')
      .split(',')
      .map(norm);
  const day = value =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date(value));
  conversations.forEach(c => {
    if (seen.has(String(c.id))) return;
    seen.add(String(c.id));
    const ctx = contexts.get(String(c.id));
    if (!ctx?.commercial_allowed || !ctx.opportunity_reference) return;
    const labels = (c.labels || []).map(norm);
    if (!labels.includes(norm(cfg.label_seguimiento))) return;
    // A client message still awaiting a human reply never becomes customer silence.
    if (
      !ctx.last_human_at ||
      !ctx.last_client_at ||
      Date.parse(ctx.last_client_at) >= Date.parse(ctx.last_human_at)
    )
      return;
    const sent = Number(ctx.follow_up?.sent_count || 0);
    const last = ctx.follow_up?.last_sent_at;
    if (ctx.state === 'inactive') {
      output.push({
        json: {
          conversation_id: c.id,
          opportunity_reference: ctx.opportunity_reference,
          accion: 'terminar',
          marcar_inactivo: true,
          labels_finales: [
            ...labels.filter(
              l =>
                l !== norm(cfg.label_seguimiento) &&
                l !== norm(cfg.label_inactivo)
            ),
            norm(cfg.label_inactivo),
          ],
        },
      });
      return;
    }
    if (ctx.state !== 'in_progress' || sent >= 3) return;
    if (
      sent > 0 &&
      (!last || (Date.parse(today) - Date.parse(day(last))) / 86400000 < 2)
    )
      return;
    const assigned = norm(
      c.meta?.assignee?.available_name || c.meta?.assignee?.name
    );
    let seller = '';
    if (aliases(cfg.alias_juli).some(a => a && assigned.includes(a)))
      seller = 'juli';
    else if (aliases(cfg.alias_marcos).some(a => a && assigned.includes(a)))
      seller = 'marcos';
    if (!seller) return;
    const advisor = seller.charAt(0).toUpperCase() + seller.slice(1);
    let product = cfg.producto_generico;
    if (labels.includes(norm(cfg.label_bici))) product = cfg.producto_bici;
    else if (labels.includes(norm(cfg.label_aparatos)))
      product = cfg.producto_aparatos;
    const step = sent + 1;
    const template = renderTemplate(
      templateConfig.commercial_templates?.[String(c.inbox_id)],
      ['seg_dia_1', 'seg_dia_3', 'seg_dia_5'][step - 1],
      cfg.template_language,
      { asesor: advisor, producto: product }
    );
    output.push({
      json: {
        conversation_id: c.id,
        opportunity_reference: ctx.opportunity_reference,
        accion: 'enviar',
        paso: step,
        envio_numero: step,
        fecha_envio: today,
        ultimo_envio_previo: last ? day(last) : '',
        vendedor: seller,
        asesor: advisor,
        producto: product,
        template_name: template.name,
        template_category: template.category,
        template_language: template.language,
        processed_params: template.processed_params,
        template_content: template.content,
      },
    });
  });
  return output;
}

const set = (nodeName, pointer, value) => ({
  type: 'setNodeParameter',
  nodeName,
  path: pointer,
  value,
});
const link = (type, source, target, sourceIndex = 0) => ({
  type,
  source,
  target,
  sourceIndex,
});
const codeNode = (name, jsCode, position) => ({
  name,
  type: 'n8n-nodes-base.code',
  typeVersion: 2,
  position,
  parameters: { mode: 'runOnceForAllItems', jsCode },
});
const base = config =>
  `$('${config}').first().json.url_chatwoot.replace(/\\/$/, '') + '/api/v1/accounts/' + $('${config}').first().json.account_number`;
function httpNode(name, url, position, method = 'GET', jsonBody = null) {
  return {
    name,
    type: 'n8n-nodes-base.httpRequest',
    typeVersion: 4.2,
    position,
    credentials: { httpHeaderAuth: { name: 'Chatwoot - admin' } },
    parameters: {
      method,
      url: '={{ ' + url + ' }}',
      authentication: 'genericCredentialType',
      genericAuthType: 'httpHeaderAuth',
      ...(jsonBody ? { sendBody: true, specifyBody: 'json', jsonBody } : {}),
      options: {
        timeout: 30000,
        response: { response: { responseFormat: 'json' } },
      },
    },
  };
}
function contextNode(name, url, position, conversationExpression) {
  const node = httpNode(
    name,
    url + " + '/arroyo/commercial/contexts'",
    position
  );
  if (conversationExpression)
    Object.assign(node.parameters, {
      sendQuery: true,
      queryParameters: {
        parameters: [
          { name: 'conversation_id', value: conversationExpression },
        ],
      },
    });
  node.parameters.options.pagination = {
    pagination: {
      paginationMode: 'updateAParameterInEachRequest',
      parameters: {
        parameters: [
          { type: 'qs', name: 'page', value: '={{ $pageCount + 1 }}' },
        ],
      },
      paginationCompleteWhen: 'other',
      completeExpression: '={{ $response.body.meta.next_page === null }}',
      limitPagesFetched: false,
      requestInterval: 150,
    },
  };
  return node;
}
function markBody(node, kind, reference) {
  const parameters = node.parameters;
  let body;
  if (parameters.jsonBody) {
    if (!parameters.jsonBody.startsWith('={{ JSON.stringify('))
      throw new Error('Unexpected message body: ' + node.name);
    body = parameters.jsonBody.match(
      /^=\{\{ JSON\.stringify\(([\s\S]*)\) \}\}$/
    )[1];
  } else {
    body =
      '{ ' +
      parameters.bodyParameters.parameters
        .map(
          field =>
            JSON.stringify(field.name) +
            ': ' +
            (field.value.startsWith('={{')
              ? field.value.slice(3, -2).trim()
              : JSON.stringify(field.value))
        )
        .join(', ') +
      ' }';
  }
  return (
    '={{ JSON.stringify(Object.assign({}, ' +
    body +
    ", { content_attributes: { arroyo_kind: '" +
    kind +
    "', arroyo_opportunity_reference: " +
    reference +
    (kind === 'commercial_follow_up' ? ', arroyo_step: $json.paso' : '') +
    ' } })) }}'
  );
}
function markedParameters(node, kind, reference) {
  const parameters = {
    ...node.parameters,
    specifyBody: 'json',
    jsonBody: markBody(node, kind, reference),
  };
  delete parameters.bodyParameters;
  return {
    type: 'updateNodeParameters',
    nodeName: node.name,
    replace: true,
    parameters,
  };
}

function buildPatches(baselines) {
  const get = id => baselines.find(item => item.workflowId === id);
  const derive = get('B5YmsSniVco8DT6Y');
  const main = get('SAGFyESTLZLDdaNo');
  const follow = get('fF0LK453uWJdBHsR');
  const patches = [main, derive, follow].map(b => ({
    workflowId: b.workflowId,
    baseVersionId: b.baseVersionId,
    activeVersionId: b.activeVersionId,
    operations: [],
  }));
  const [mo, de, fo] = patches.map(p => p.operations);
  const node = (b, name) => {
    const found = b.nodes.find(n => n.name === name);
    if (!found) throw new Error('Missing baseline node: ' + name);
    return found;
  };
  const dctx = contextNode(
    'Contexto Comercial Derivacion',
    base('DatosWSP'),
    [144, 144],
    "={{ $('DatosWSP').first().json.conversation_id }}"
  );
  const balanced = {
    name: 'Reparto con Historial?',
    type: 'n8n-nodes-base.if',
    typeVersion: 2.2,
    position: [784, 192],
    parameters: {
      conditions: {
        options: {
          caseSensitive: true,
          leftValue: '',
          typeValidation: 'strict',
          version: 2,
        },
        combinator: 'and',
        conditions: [
          {
            id: 'balanced',
            leftValue:
              "={{ $('Contexto Comercial Derivacion').first().json.config.funnel_enabled === true && $('Contexto Comercial Derivacion').first().json.config.balanced_assignment_enabled === true }}",
            rightValue: '',
            operator: { type: 'boolean', operation: 'true', singleValue: true },
          },
        ],
      },
      options: {},
    },
  };
  const assign = httpNode(
    'Asignar en Chatwoot Arroyo',
    base('DatosWSP') + " + '/arroyo/commercial/assign'",
    [1040, 144],
    'POST',
    "={{ JSON.stringify({ conversation_id: $('DatosWSP').first().json.conversation_id }) }}"
  );
  const effective = codeNode(
    'Responsable Efectivo',
    "const cfg = $('Contexto Comercial Derivacion').first().json.config;\nif (cfg.funnel_enabled === true && cfg.balanced_assignment_enabled === true) {\n  const assigned = $input.first().json;\n  if (!assigned.assigned || !assigned.assignee_id) return [];\n  return [{ json: { agent_id: assigned.assignee_id, opportunity_reference: assigned.opportunity_reference } }];\n}\nreturn [{ json: $('agents1').first().json }];",
    [1776, 192]
  );
  de.push(
    ...[dctx, balanced, assign, effective].map(n => ({
      type: 'addNode',
      node: n,
    })),
    link('removeConnection', 'DatosWSP', 'Tomar Candado'),
    link('addConnection', 'DatosWSP', dctx.name),
    link('addConnection', dctx.name, 'Tomar Candado'),
    link('removeConnection', 'StatusOpen1', 'Tomar Turno'),
    link('addConnection', 'StatusOpen1', balanced.name),
    link('addConnection', balanced.name, assign.name),
    link('addConnection', balanced.name, 'Tomar Turno', 1),
    link('addConnection', assign.name, effective.name),
    link('removeConnection', 'Asignar agente1', 'If'),
    link('addConnection', 'Asignar agente1', effective.name),
    link('addConnection', effective.name, 'If'),
    set('If', '/conditions/conditions/0/leftValue', '={{ $json.agent_id }}'),
    set(
      'Tomar Candado',
      '/key',
      "={{ 'v2:derivado:' + $('DatosWSP').first().json.conversation_id + ($('Contexto Comercial Derivacion').first().json.config.funnel_enabled === true ? ':' + ($('Contexto Comercial Derivacion').first().json.contexts[0]?.opportunity_reference || 'pending') : '') }}"
    )
  );
  ['juli', 'marcos', 'Aviso Derivacion'].forEach(name => {
    de.push(
      markedParameters(
        node(derive, name),
        'assignment_greeting',
        (name === 'Aviso Derivacion'
          ? ''
          : "$('Responsable Efectivo').first().json.opportunity_reference || ") +
          "$('Contexto Comercial Derivacion').first().json.contexts[0]?.opportunity_reference || null"
      )
    );
  });
  const mctx = contextNode(
    'Contexto Comercial Bot',
    "'https://chatarroyo.thorque.com.ar/api/v1/accounts/1'",
    [2640, -96],
    "={{ $('Preparar Datos').first().json.conversation_id }}"
  );
  mo.push(
    { type: 'addNode', node: mctx },
    link('removeConnection', 'Preparar Datos', 'Leer Pregunta Localidad'),
    link('addConnection', 'Preparar Datos', mctx.name),
    link('addConnection', mctx.name, 'Leer Pregunta Localidad'),
    markedParameters(
      node(main, 'Enviar Saludo'),
      'bot',
      "$('Contexto Comercial Bot').first().json.contexts[0]?.opportunity_reference || null"
    )
  );
  const contexts = contextNode(
    'Contextos Comerciales',
    base('Config Chatwoot'),
    [-336, 416]
  );
  const controlledSend = httpNode(
    'Enviar Seguimiento Arroyo',
    base('Config Chatwoot') + " + '/arroyo/commercial/follow_up/message'",
    [784, 624],
    'POST',
    '={{ JSON.stringify({ conversation_id: $json.conversation_id, opportunity_reference: $json.opportunity_reference, step: $json.paso, content: $json.template_content, template_params: { name: $json.template_name, category: $json.template_category, language: $json.template_language, processed_params: $json.processed_params } }) }}'
  );
  const sendGate = JSON.parse(JSON.stringify(balanced));
  sendGate.name = 'Envio Comercial Controlado?';
  sendGate.position = [656, 800];
  sendGate.parameters.conditions.conditions[0].leftValue =
    "={{ $('Contextos Comerciales').first().json.config.funnel_enabled === true }}";
  const legacy = node(follow, 'Clasificar Seguimiento Diario').parameters
    .jsCode;
  const templateFunction = legacy.slice(0, legacy.indexOf('// Pure functions'));
  const classifier =
    templateFunction +
    '\n' +
    classifyCommercial.toString() +
    "\nconst contextPages = $('Contextos Comerciales').all().map(item => item.json);\nif (contextPages[0].config.funnel_enabled === true) {\n  const cfg = $('Config Chatwoot').first().json;\n  const now = $now.setZone('America/Argentina/Buenos_Aires');\n  if (String(cfg.dias_sin_envio || '').split(',').map(Number).includes(now.weekday)) return [];\n  return classifyCommercial($input.all().flatMap(item => item.json.payload ?? item.json.data?.payload ?? []), contextPages, cfg, $('Compras para Coordinacion Comercial').first().json.config, now.toISO(), commercialTemplate);\n}\n" +
    '(function legacyClassifier() {\n' +
    legacy +
    '\n})()';
  // The final return preserves the complete published classifier when funnel is disabled.
  const finalClassifier = classifier.replace(
    '(function legacyClassifier()',
    'return (function legacyClassifier()'
  );
  fo.push(
    { type: 'addNode', node: contexts },
    { type: 'addNode', node: controlledSend },
    { type: 'addNode', node: sendGate },
    {
      type: 'setNodeSettings',
      nodeName: controlledSend.name,
      settings: { onError: 'continueRegularOutput', retryOnFail: false },
    },
    link(
      'removeConnection',
      'Terminar Secuencia?',
      'Enviar Seguimiento Diario',
      1
    ),
    link('addConnection', 'Terminar Secuencia?', sendGate.name, 1),
    link('addConnection', sendGate.name, controlledSend.name),
    link('addConnection', sendGate.name, 'Enviar Seguimiento Diario', 1),
    link('addConnection', controlledSend.name, 'Se Mando?'),
    {
      type: 'setNodeSettings',
      nodeName: contexts.name,
      settings: { executeOnce: true },
    },
    {
      type: 'addNode',
      node: codeNode(
        'Continuar Comercial Una Vez',
        'return [{ json: {} }];',
        [-224, 416]
      ),
    },
    link(
      'removeConnection',
      'Compras para Coordinacion Comercial',
      'Hoy Se Manda?'
    ),
    link('addConnection', 'Compras para Coordinacion Comercial', contexts.name),
    link('addConnection', contexts.name, 'Continuar Comercial Una Vez'),
    link('addConnection', 'Continuar Comercial Una Vez', 'Hoy Se Manda?'),
    set('Clasificar Seguimiento Diario', '/jsCode', finalClassifier),
    set(
      'Enviar Seguimiento Diario',
      '/jsonBody',
      markBody(
        node(follow, 'Enviar Seguimiento Diario'),
        'commercial_follow_up',
        '$json.opportunity_reference || null'
      )
    )
  );
  return patches;
}

if (require.main === module) {
  const baseline = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, 'commercial-funnel-baseline.json'),
      'utf8'
    )
  );
  fs.writeFileSync(
    path.join(__dirname, 'commercial-funnel-operations.json'),
    JSON.stringify(buildPatches(baseline), null, 2) + '\n'
  );
}
module.exports = { buildPatches };
