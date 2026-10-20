const fs = require('node:fs');
const path = require('node:path');

// Embedded unchanged in the commercial Code node; metadata comes from Chatwoot's sanitized Meta cache.
function commercialTemplate(templates, name, language, variables) {
  const template = (templates || []).find(
    item =>
      item.name === name &&
      item.language?.toLowerCase() === language?.toLowerCase() &&
      item.status?.toLowerCase() === 'approved'
  );
  const body = template?.components?.find(item => item.type === 'BODY')?.text;
  const names = [
    ...new Set(
      [...(body || '').matchAll(/\{\{\s*([^{}]+?)\s*\}\}/g)].map(
        match => match[1]
      )
    ),
  ];
  const unsupported = template?.components?.some(
    item =>
      (item.type === 'HEADER' && item.format !== 'TEXT') ||
      (item.type !== 'BODY' && JSON.stringify(item).includes('{{'))
  );
  if (
    !body ||
    unsupported ||
    (names.length && template.parameter_format !== 'NAMED') ||
    names.some(key => !variables[key]?.trim())
  ) {
    throw new Error(
      'Plantilla Meta no disponible o parametros incompletos: ' + name
    );
  }
  return {
    name: template.name,
    category: template.category,
    language: template.language,
    processed_params: {
      body: Object.fromEntries(names.map(key => [key, variables[key]])),
    },
    content: body.replace(
      /\{\{\s*([^{}]+?)\s*\}\}/g,
      (match, key) => variables[key]
    ),
  };
}

function templateClassifier(code) {
  if (code.includes('const templateMessage = commercialTemplate(')) return code;
  const send =
    "  salida.push({ json: {\n    conversation_id: c.id,\n    accion: 'enviar',";
  if (!code.includes(send) || !code.includes('const FALLBACKS = ['))
    throw new Error('Review changed commercial classifier');
  return (
    commercialTemplate.toString() +
    '\n' +
    code
      .replace(/\/\/ Texto de respaldo[\s\S]*?const cap =/, 'const cap =')
      .replace(
        'const SECUENCIA = [cfg.template_seg_dia_1, cfg.template_seg_dia_3, cfg.template_seg_dia_5];',
        "const SECUENCIA = ['seg_dia_1', 'seg_dia_3', 'seg_dia_5'];"
      )
      .replace(
        send,
        "  const templateMessage = commercialTemplate($('Compras para Coordinacion Comercial').first().json.config.commercial_templates?.[String(c.inbox_id)], SECUENCIA[envioNumero - 1], cfg.template_language, { asesor, producto });\n" +
          send
      )
      .replace(
        "template_category: cfg.categoria_seguimiento ?? 'MARKETING'",
        'template_category: templateMessage.category'
      )
      .replace(
        'template_language: cfg.template_language,',
        'template_language: templateMessage.language,'
      )
      .replace(
        'processed_params: { asesor: asesor, producto: producto },',
        'processed_params: templateMessage.processed_params,'
      )
      .replace(
        'fallback: FALLBACKS[envioNumero - 1](asesor, producto),',
        'template_content: templateMessage.content,'
      )
  );
}

function buildTemplateOperations(workflow) {
  const helpers = fs
    .readFileSync(path.join(__dirname, 'post_sale-transform.cjs'), 'utf8')
    .split('module.exports =')[0];
  const classifier = workflow.nodes.find(
    node => node.name === 'Clasificar Seguimiento Diario'
  ).parameters.jsCode;
  const commercialEntry = classifier.indexOf(
    'const activePostSaleConversations'
  );
  if (commercialEntry < 0)
    throw new Error('Review changed commercial coordination');
  const names = ['Preparar Compras Postventa', 'Seleccionar Etapas Postventa'];
  const operations = names.map(nodeName => {
    const current = workflow.nodes.find(node => node.name === nodeName)
      .parameters.jsCode;
    const entry =
      nodeName === names[0]
        ? '\nreturn purchaseItems('
        : "\nconst config = $('Leer Compras Postventa')";
    const index = current.indexOf(entry);
    if (index < 0)
      throw new Error('Review changed post-sale Code node: ' + nodeName);
    return {
      type: 'setNodeParameter',
      nodeName,
      path: '/jsCode',
      value: helpers + current.slice(index),
    };
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Clasificar Seguimiento Diario',
    path: '/jsCode',
    value: templateClassifier(
      helpers + '\n' + classifier.slice(commercialEntry)
    ),
  });
  operations.push({
    type: 'setNodeParameter',
    nodeName: 'Enviar Seguimiento Diario',
    path: '/jsonBody',
    value:
      "={{ JSON.stringify({ content: $json.template_content, message_type: 'outgoing', private: false, template_params: { name: $json.template_name, category: $json.template_category, language: $json.template_language, processed_params: $json.processed_params } }) }}",
  });
  return { workflowId: workflow.id, operations };
}

module.exports = {
  commercialTemplate,
  templateClassifier,
  buildTemplateOperations,
};
