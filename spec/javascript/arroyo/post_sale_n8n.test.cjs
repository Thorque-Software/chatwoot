const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {
  buildOperations,
} = require('../../../docs/arroyo/n8n/post_sale-build.cjs');
const baseline = require('../../../docs/arroyo/n8n/post_sale-baseline.json');
const {
  planPurchase,
  purchaseItems,
  dueMessages,
  activeConversationIds,
} = require('../../../docs/arroyo/n8n/post_sale-transform.cjs');

const config = {
  enabled: true,
  timezone: 'America/Argentina/Buenos_Aires',
  send_hour_local: 10,
  skip_sundays: false,
  delivery_timeout_hours: 6,
  template_language: 'es_AR',
  stages: Object.fromEntries(
    [
      ['d1', 1],
      ['d7', 7],
      ['d30', 30],
    ].map(([stage, days]) => [
      stage,
      {
        days,
        free_text:
          'Hola {{contact.first_name}}, soy {{vendedor}}. ¿Cómo va {{producto}}?',
        template: 'postventa_' + stage,
      },
    ])
  ),
};
const purchase = {
  reference: 'purchase-fixture',
  revision: 1,
  planned_revision: 1,
  purchased_at: '2026-10-13T22:00:00-03:00',
  conversation_id: 77,
  product: 'tu bicicleta',
  seller: { id: 12, name: 'Julieta' },
  contact: { id: 3, name: 'Ana Pérez' },
  can_reply: true,
  inbox: { id: 5, channel_type: 'Channel::Whatsapp', message_templates: [] },
  follow_ups: [
    {
      id: 8,
      stage: 'd1',
      status: 'scheduled',
      scheduled_at: '2026-10-14T13:00:00Z',
      message_id: null,
    },
  ],
};

test('dates follow purchase local calendar, including D7 and all-region D30', () => {
  assert.deepEqual(planPurchase(purchase, config), {
    revision: 1,
    stages: {
      d1: '2026-10-14T13:00:00.000Z',
      d7: '2026-10-20T13:00:00.000Z',
      d30: '2026-11-12T13:00:00.000Z',
    },
  });
});
test('calendar respects timezone, year rollover and optional Sunday skip', () => {
  assert.equal(
    planPurchase({ ...purchase, purchased_at: '2026-12-31T01:00:00Z' }, config)
      .stages.d1,
    '2026-12-31T13:00:00.000Z'
  );
  assert.equal(
    planPurchase(
      { ...purchase, purchased_at: '2026-10-17T23:00:00-03:00' },
      { ...config, skip_sundays: true }
    ).stages.d1,
    '2026-10-19T13:00:00.000Z'
  );
});
test('configuration disabled emits no plans, sends or commercial exclusions', () => {
  const disabled = { ...config, enabled: false };
  assert.deepEqual(
    purchaseItems([{ config: disabled, purchases: [purchase] }]),
    []
  );
  assert.deepEqual(dueMessages(purchase, disabled, '2026-10-14T13:00:00Z'), []);
  assert.deepEqual(
    activeConversationIds([{ config: disabled, purchases: [purchase] }]),
    []
  );
});
test('pagination duplicates purchases once and commercial exclusion includes completed stages', () => {
  const pages = [
    { config, purchases: [purchase] },
    { config, purchases: [purchase] },
  ];
  assert.equal(purchaseItems(pages).length, 1);
  assert.deepEqual(activeConversationIds(pages), ['77']);
});
test('due send uses actual contact, product, seller and execution ID', () => {
  assert.deepEqual(
    dueMessages(purchase, config, '2026-10-14T13:00:00Z', 'fixture-run'),
    [
      {
        id: 8,
        reference: 'purchase-fixture',
        conversation_id: 77,
        stage: 'd1',
        body: {
          revision: 1,
          content: 'Hola Ana, soy Julieta. ¿Cómo va tu bicicleta?',
          execution_id: 'fixture-run',
        },
      },
    ]
  );
});

test('nullable contact and original seller names do not abort a due batch', () => {
  const item = {
    ...purchase,
    contact: { ...purchase.contact, name: null },
    seller: null,
    product: null,
  };
  assert.equal(
    dueMessages(item, config, '2026-10-14T13:00:00Z')[0].body.content,
    'Hola , soy . ¿Cómo va ?'
  );
});
test('stale revisions, attempted/message stages, future or old stages never dispatch', () => {
  assert.deepEqual(
    dueMessages({ ...purchase, revision: 2 }, config, '2026-10-14T13:00:00Z'),
    []
  );
  [
    { status: 'failed' },
    { attempted_at: '2026-10-14T13:00:00Z' },
    { message_id: 99 },
  ].forEach(change => {
    assert.deepEqual(
      dueMessages(
        { ...purchase, follow_ups: [{ ...purchase.follow_ups[0], ...change }] },
        config,
        '2026-10-14T13:00:00Z'
      ),
      []
    );
  });
  assert.deepEqual(dueMessages(purchase, config, '2026-10-14T12:59:59Z'), []);
  assert.deepEqual(dueMessages(purchase, config, '2026-10-15T13:00:00Z'), []);
});
test('approved named template derives actual metadata and body parameter names', () => {
  const template = {
    name: 'postventa_d1',
    language: 'es_AR',
    status: 'APPROVED',
    category: 'MARKETING',
    parameter_format: 'NAMED',
    components: [
      {
        type: 'BODY',
        text: 'Hola {{nombre}}, soy {{asesor}}. ¿Cómo va {{producto}}?',
      },
    ],
  };
  const item = {
    ...purchase,
    can_reply: false,
    inbox: { ...purchase.inbox, message_templates: [template] },
  };
  assert.deepEqual(
    dueMessages(item, config, '2026-10-14T13:00:00Z')[0].body.template_params,
    {
      name: 'postventa_d1',
      category: 'MARKETING',
      language: 'es_AR',
      processed_params: {
        body: { nombre: 'Ana', asesor: 'Julieta', producto: 'tu bicicleta' },
      },
    }
  );
});
test('missing, unapproved, positional and unsupported template variables omit template for visible backend failure', () => {
  [
    { status: 'PENDING' },
    { parameter_format: 'POSITIONAL' },
    { components: [{ type: 'BODY', text: '{{unknown}}' }] },
    { components: [{ type: 'HEADER', format: 'IMAGE' }] },
  ].forEach(extra => {
    const template = {
      name: 'postventa_d1',
      language: 'es_AR',
      status: 'APPROVED',
      category: 'MARKETING',
      parameter_format: 'NAMED',
      components: [{ type: 'BODY', text: '{{nombre}}' }],
      ...extra,
    };
    const item = {
      ...purchase,
      can_reply: false,
      inbox: { ...purchase.inbox, message_templates: [template] },
    };
    assert.equal(
      dueMessages(item, config, '2026-10-14T13:00:00Z')[0].body.template_params,
      undefined
    );
  });
});

function runCode(code, inputs, linkedNodes, now = '2026-10-14T13:00:00Z') {
  // Only the n8n clock is substituted; the full production Code node runs unchanged.
  const clock = {
    setZone() {
      return this;
    },
    toISO: () => now,
    toSeconds: () => Date.parse(now) / 1000,
    toFormat: () => '2026-10-14',
    weekday: 3,
  };
  return vm.runInNewContext('(function(){' + code + '\n})()', {
    $input: { all: () => inputs },
    $: name => linkedNodes[name],
    $now: clock,
    $execution: { id: 'fixture-run' },
    console: { log() {} },
  });
}

test('generated Code nodes run both existing and PUT response contracts without module imports', () => {
  const { operations } = buildOperations(baseline);
  const nodes = operations
    .filter(operation => operation.type === 'addNode')
    .map(operation => operation.node);
  const prepare = nodes.find(
    node => node.name === 'Preparar Compras Postventa'
  );
  const select = nodes.find(
    node => node.name === 'Seleccionar Etapas Postventa'
  );
  const linked = {
    'Leer Compras Postventa': { first: () => ({ json: { config } }) },
  };
  const prepared = runCode(
    prepare.parameters.jsCode,
    [{ json: { config, purchases: [purchase] } }],
    linked
  );
  assert.equal(prepared[0].json.needs_plan, false);
  assert.equal(
    runCode(select.parameters.jsCode, prepared, linked)[0].json.body.content,
    'Hola Ana, soy Julieta. ¿Cómo va tu bicicleta?'
  );
  assert.equal(
    runCode(select.parameters.jsCode, [{ json: { purchase } }], linked)[0].json
      .id,
    8
  );
  assert.equal(
    runCode(select.parameters.jsCode, [{ json: { error: 'HTTP 409' } }], linked)
      .length,
    0
  );
});

test('commercial classification preserves legacy behavior and excludes only registered purchases', () => {
  const cfg = {
    label_seguimiento: 'seguimiento',
    label_inactivo: 'inactivo',
    alias_juli: 'juli,julieta',
    template_seg_dia_1: 'seg_dia_1',
    template_language: 'es_AR',
    producto_generico: 'la bicicleta',
  };
  const inputs = [
    {
      json: {
        payload: [
          {
            id: 77,
            labels: ['seguimiento'],
            last_activity_at: Date.parse('2026-10-14T12:00:00Z') / 1000,
            meta: {
              assignee: { name: 'Julieta' },
              sender: { name: 'Ana Pérez' },
            },
          },
        ],
      },
    },
  ];
  const linked = {
    'Config Chatwoot': { first: () => ({ json: cfg }) },
    'Compras para Coordinacion Comercial': {
      all: () => [{ json: { config, purchases: [] } }],
    },
  };
  const code = buildOperations(baseline).operations.find(
    operation => operation.nodeName === 'Clasificar Seguimiento Diario'
  ).value;
  const legacy = runCode(baseline.commercialClassifier, inputs, linked);
  assert.equal(legacy.length, 1);
  assert.deepEqual(
    JSON.parse(JSON.stringify(runCode(code, inputs, linked))),
    JSON.parse(JSON.stringify(legacy))
  );
  linked['Compras para Coordinacion Comercial'].all = () => [
    { json: { config, purchases: [purchase] } },
  ];
  assert.equal(runCode(code, inputs, linked).length, 0);
});

test('post-sale polling cannot reach the daily commercial branch', () => {
  const operations = buildOperations(baseline).operations;
  const links = operations.filter(
    operation => operation.type === 'addConnection'
  );
  const reachable = new Set(['Postventa Cada 15 Minutos']);
  for (let pass = 0; pass < links.length; pass += 1)
    links.forEach(link => {
      if (reachable.has(link.source)) reachable.add(link.target);
    });
  assert.equal(reachable.has('Crear Mensaje Postventa'), true);
  assert.equal(reachable.has('Hoy Se Manda?'), false);
  assert.equal(reachable.has('Config Chatwoot'), false);
});
