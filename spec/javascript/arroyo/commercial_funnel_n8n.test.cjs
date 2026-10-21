const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {
  buildPatches,
} = require('../../../docs/arroyo/n8n/commercial-funnel-build.cjs');
const baseline = require('../../../docs/arroyo/n8n/commercial-funnel-baseline.json');

const patches = () => buildPatches(baseline);
const patch = id => patches().find(item => item.workflowId === id);
const follow = () => patch('fF0LK453uWJdBHsR');
const code = () =>
  follow().operations.find(
    op =>
      op.nodeName === 'Clasificar Seguimiento Diario' && op.path === '/jsCode'
  ).value;
const cfg = Object.fromEntries(
  baseline[2].nodes
    .find(n => n.name === 'Config Chatwoot')
    .parameters.assignments.assignments.map(a => [a.name, a.value])
);
const template = {
  name: 'seg_dia_1',
  language: cfg.template_language,
  category: 'MARKETING',
  status: 'APPROVED',
  parameter_format: 'NAMED',
  components: [{ type: 'BODY', text: 'Hola {{asesor}}, {{producto}}' }],
};
const conversation = id => ({
  id,
  inbox_id: 2,
  labels: ['seguimiento'],
  last_activity_at: 1,
  custom_attributes: { seguimiento_envios: 3 },
  meta: { assignee: { name: 'Julieta' } },
});
const context = id => ({
  conversation_id: id,
  opportunity_reference: `op-${id}`,
  state: 'in_progress',
  commercial_allowed: true,
  last_human_at: '2026-10-19T12:00:00Z',
  last_client_at: '2026-10-18T12:00:00Z',
  follow_up: {
    active: true,
    sent_count: 0,
    last_sent_at: null,
    due: true,
    finish_due: false,
  },
});
test('incremental graph operations reference existing nodes and preserve error branches', () => {
  patches().forEach(p => {
    const original = baseline.find(b => b.workflowId === p.workflowId);
    const names = new Set(original.nodeNames);
    const connections = new Set(
      Object.entries(original.connections).flatMap(([source, types]) =>
        (types.main || []).flatMap((targets, index) =>
          (targets || []).map(target => `${source}:${index}:${target.node}`)
        )
      )
    );
    p.operations.forEach(op => {
      if (op.type === 'addNode') {
        assert.ok(!names.has(op.node.name));
        names.add(op.node.name);
      }
      if (op.source) {
        assert.ok(names.has(op.source));
        assert.ok(names.has(op.target));
        const key = `${op.source}:${op.sourceIndex || 0}:${op.target}`;
        if (op.type === 'removeConnection') {
          assert.ok(connections.has(key), `missing ${key}`);
          connections.delete(key);
        } else {
          assert.ok(!connections.has(key), `duplicate ${key}`);
          connections.add(key);
        }
      }
    });
    if (p.workflowId === 'B5YmsSniVco8DT6Y')
      assert.ok(connections.has('Asignar agente1:1:Nota Error Derivacion'));
  });
});
function classify(conversations, contexts, enabled = true) {
  const pages = [
    {
      json: {
        config: { funnel_enabled: enabled },
        contexts: contexts.slice(0, 200),
      },
    },
    { json: { contexts: contexts.slice(200) } },
  ];
  return vm.runInNewContext('(function(){' + code() + '\n})()', {
    $: name => ({
      first: () => {
        if (name === 'Config Chatwoot') return { json: cfg };
        if (name === 'Contextos Comerciales') return pages[0];
        return {
          json: {
            config: {
              enabled: true,
              commercial_templates: {
                2: ['seg_dia_1', 'seg_dia_3', 'seg_dia_5'].map(
                  templateName => ({
                    ...template,
                    name: templateName,
                  })
                ),
              },
            },
            purchases: [],
          },
        };
      },
      all: () =>
        name === 'Contextos Comerciales'
          ? pages
          : [{ json: { config: { enabled: true }, purchases: [] } }],
    }),
    $input: { all: () => [{ json: { payload: conversations } }] },
    $now: {
      setZone() {
        return this;
      },
      weekday: 2,
      toFormat: () => '2026-10-20',
      toISO: () => '2026-10-20T13:00:00Z',
      toSeconds: () => Date.parse('2026-10-20T13:00:00Z') / 1000,
    },
    console: { log() {} },
  });
}
test('version-pinned incremental artifacts preserve postventa and recipient pagination', () => {
  assert.equal(patches().length, 3);
  patches().forEach(p => {
    assert.equal(
      p.baseVersionId,
      baseline.find(b => b.workflowId === p.workflowId).baseVersionId
    );
    assert.ok(p.operations.length <= 100);
    assert.ok(
      p.operations.every(
        op => !/Postventa|Buscar Chats con Seguimiento/.test(op.nodeName || '')
      )
    );
  });
  const read = follow().operations.find(
    op => op.type === 'addNode' && op.node.name === 'Contextos Comerciales'
  ).node;
  assert.equal(
    read.parameters.options.pagination.pagination.limitPagesFetched,
    false
  );
});
test('new opportunity ignores old conversation counters and old activity timestamp', () => {
  const output = classify([conversation(1)], [context(1)]);
  assert.equal(output.length, 1);
  assert.equal(output[0].json.paso, 1);
  assert.equal(output[0].json.opportunity_reference, 'op-1');
});
test('a customer reply does not stop enrollment, but missing context and sold support remain excluded', () => {
  const pending = { ...context(1), last_client_at: '2026-10-20T12:00:00Z' };
  const won = { ...context(2), state: 'won', commercial_allowed: false };
  assert.equal(
    classify(
      [conversation(1), conversation(2), conversation(3)],
      [pending, won]
    ).length,
    1
  );
});

test('the first followup waits for the backend enrollment date, regardless of human messages', () => {
  const ctx = { ...context(1), state: 'pending', last_human_at: null };
  ctx.follow_up = {
    ...ctx.follow_up,
    due: false,
    next_at: '2026-10-21T13:00:00Z',
  };
  assert.equal(classify([conversation(1)], [ctx]).length, 0);
  ctx.follow_up.due = true;
  assert.equal(classify([conversation(1)], [ctx])[0].json.paso, 1);
});

test('removing seguimiento stops dispatch even if a stale backend context says due', () => {
  assert.equal(
    classify([{ ...conversation(1), labels: [] }], [context(1)]).length,
    0
  );
});
test('backend customer inactivity survives unrelated activity and uses backend classification', () => {
  const c = {
    ...conversation(1),
    last_activity_at: Date.parse('2026-10-20T12:30:00Z') / 1000,
  };
  const result = classify(
    [c],
    [
      {
        ...context(1),
        state: 'inactive',
        follow_up: {
          active: true,
          sent_count: 3,
          last_sent_at: '2026-10-17T13:00:00Z',
          finish_due: true,
        },
      },
    ]
  );
  assert.equal(result[0].json.marcar_inactivo, true);
  assert.equal(result[0].json.accion, 'terminar');
  assert.equal(
    classify(
      [c],
      [
        {
          ...context(1),
          follow_up: { sent_count: 3, last_sent_at: '2026-10-17T13:00:00Z' },
        },
      ]
    ).length,
    0
  );
});
test('two calendar days between successful sends remain required', () => {
  const ctx = {
    ...context(1),
    follow_up: {
      active: true,
      sent_count: 1,
      last_sent_at: '2026-10-19T13:00:00Z',
      due: false,
    },
  };
  assert.equal(classify([conversation(1)], [ctx]).length, 0);
  const due = {
    ...ctx,
    follow_up: {
      active: true,
      sent_count: 1,
      last_sent_at: '2026-10-18T13:00:00Z',
      due: true,
    },
  };
  assert.equal(classify([conversation(1)], [due])[0].json.paso, 2);
});
test('all contexts pages and recipients are processed once', () => {
  const cs = Array.from({ length: 401 }, (_, i) => conversation(i + 1));
  const output = classify(
    cs.concat(cs),
    cs.map(c => context(c.id))
  );
  assert.equal(output.length, 401);
  const collapse = follow().operations.find(
    op =>
      op.type === 'addNode' && op.node.name === 'Continuar Comercial Una Vez'
  ).node.parameters.jsCode;
  assert.equal(
    vm.runInNewContext('(function(){' + collapse + '})()', {
      $input: { all: () => cs },
    }).length,
    1
  );
  assert.ok(
    follow().operations.some(
      op =>
        op.type === 'setNodeSettings' &&
        op.nodeName === 'Contextos Comerciales' &&
        op.settings.executeOnce
    )
  );
});
test('flag on sends through the atomic backend while flag off keeps the native bot credential', () => {
  const operations = follow().operations;
  const send = operations.find(
    op => op.type === 'addNode' && op.node.name === 'Enviar Seguimiento Arroyo'
  ).node;
  assert.match(send.parameters.url, /commercial\/follow_up\/message/);
  assert.equal(send.credentials.httpHeaderAuth.name, 'Chatwoot - admin');
  assert.ok(
    !operations.some(
      op =>
        op.type === 'setNodeCredential' &&
        op.nodeName === 'Enviar Seguimiento Diario'
    )
  );
  const body = JSON.parse(
    vm.runInNewContext(send.parameters.jsonBody.slice(3, -2), {
      $json: {
        conversation_id: 10,
        opportunity_reference: 'op-2',
        paso: 2,
        template_name: 'seg_dia_3',
        template_language: 'es_AR',
      },
    })
  );
  assert.equal(body.opportunity_reference, 'op-2');
  assert.equal(body.step, 2);
  assert.equal(body.template_params.name, 'seg_dia_3');
  const gate = operations.find(
    op =>
      op.type === 'addNode' && op.node.name === 'Envio Comercial Controlado?'
  ).node.parameters.conditions.conditions[0].leftValue;
  [true, false].forEach(flag =>
    assert.equal(
      vm.runInNewContext(gate.slice(3, -2), {
        $: () => ({
          first: () => ({ json: { config: { funnel_enabled: flag } } }),
        }),
      }),
      flag
    )
  );
});
test('flags off execute the unchanged legacy classifier', () => {
  const c = {
    ...conversation(1),
    last_activity_at: Date.parse('2026-10-20T12:00:00Z') / 1000,
    custom_attributes: {},
  };
  const result = classify([c], [], false);
  assert.equal(result.length, 1);
  assert.equal(result[0].json.paso, 1);
});
test('atomic assignment result respects manual ownership and never selects a local seller', () => {
  const d = patch('B5YmsSniVco8DT6Y');
  const selector = d.operations.find(
    op => op.type === 'addNode' && op.node.name === 'Responsable Efectivo'
  ).node.parameters.jsCode;
  const run = response =>
    vm.runInNewContext('(function(){' + selector + '\n})()', {
      $input: { first: () => ({ json: response }) },
      $: name => ({
        first: () => ({
          json:
            name === 'Contexto Comercial Derivacion'
              ? {
                  config: {
                    funnel_enabled: true,
                    balanced_assignment_enabled: true,
                  },
                }
              : { agent_id: 4 },
        }),
      }),
    });
  assert.equal(
    run({ assignee_id: 5, assigned: false, opportunity_reference: 'op' })
      .length,
    0
  );
  assert.equal(
    run({ assignee_id: 5, assigned: true, opportunity_reference: 'op' })[0].json
      .agent_id,
    5
  );
  assert.ok(
    d.operations.some(
      op =>
        op.type === 'removeConnection' &&
        op.source === 'StatusOpen1' &&
        op.target === 'Tomar Turno'
    )
  );
});
test('all outgoing greeting, bot and Meta followup nodes receive explicit automation markers', () => {
  const expected = [
    'Enviar Saludo',
    'juli',
    'marcos',
    'Aviso Derivacion',
    'Enviar Seguimiento Diario',
  ];
  const operations = patches().flatMap(p => p.operations);
  expected.forEach(name => {
    const op = operations.find(
      candidate =>
        candidate.nodeName === name &&
        (candidate.path === '/jsonBody' || candidate.parameters?.jsonBody)
    );
    const body = op.parameters?.jsonBody || op.value;
    assert.match(body, /arroyo_kind/);
    assert.match(body, /arroyo_opportunity_reference/);
    const rendered = vm.runInNewContext(body.slice(3, -2), {
      $json: {
        nombre_limpio: 'Prueba',
        paso: 1,
        opportunity_reference: 'op-fixture',
      },
      $: () => ({
        first: () => ({
          json: {
            opportunity_reference: 'op-fixture',
            contexts: [{ opportunity_reference: 'op-fixture' }],
          },
        }),
        item: { json: { fuera_de_horario: 'no', nombre: 'Prueba' } },
      }),
      $now: { setZone: () => ({ hour: 10 }) },
    });
    assert.equal(JSON.parse(rendered).message_type, 'outgoing');
    assert.equal(
      JSON.parse(rendered).content_attributes.arroyo_opportunity_reference,
      'op-fixture'
    );
  });
  const send = operations.find(
    op => op.nodeName === 'Enviar Seguimiento Diario' && op.path === '/jsonBody'
  );
  assert.match(send.value, /template_params/);
  assert.match(send.value, /arroyo_step/);
});
