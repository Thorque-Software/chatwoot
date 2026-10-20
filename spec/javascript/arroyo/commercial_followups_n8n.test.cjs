const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {
  buildOperations,
} = require('../../../docs/arroyo/n8n/post_sale-build.cjs');
const baseline = require('../../../docs/arroyo/n8n/post_sale-baseline.json');
function operation(name, path) {
  return buildOperations(baseline).operations.find(
    op => op.nodeName === name && op.path === path
  );
}
function classify(date, conversations) {
  const cfg = Object.fromEntries(
    baseline.commercialAssignments.map(a => [a.name, a.value])
  );
  const code = operation('Clasificar Seguimiento Diario', '/jsCode').value;
  return vm.runInNewContext('(function(){' + code + '\n})()', {
    $: name =>
      name === 'Config Chatwoot'
        ? { first: () => ({ json: cfg }) }
        : {
            first: () => ({
              json: {
                config: {
                  enabled: true,
                  commercial_templates: {
                    2: [
                      {
                        name: 'seg_dia_1',
                        language: 'es_AR',
                        category: 'MARKETING',
                        status: 'APPROVED',
                        parameter_format: 'NAMED',
                        components: [
                          {
                            type: 'BODY',
                            text: 'Hola {{asesor}}, {{producto}}',
                          },
                        ],
                      },
                      {
                        name: 'seg_dia_3',
                        language: 'es_AR',
                        category: 'MARKETING',
                        status: 'APPROVED',
                        parameter_format: 'NAMED',
                        components: [
                          {
                            type: 'BODY',
                            text: 'Hola {{asesor}}, {{producto}}',
                          },
                        ],
                      },
                      {
                        name: 'seg_dia_5',
                        language: 'es_AR',
                        category: 'MARKETING',
                        status: 'APPROVED',
                        parameter_format: 'NAMED',
                        components: [
                          {
                            type: 'BODY',
                            text: 'Hola {{asesor}}, {{producto}}',
                          },
                        ],
                      },
                    ],
                  },
                },
              },
            }),
            all: () => [{ json: { config: { enabled: true }, purchases: [] } }],
          },
    $input: { all: () => [{ json: { payload: conversations } }] },
    $now: {
      setZone() {
        return this;
      },
      weekday: date === '2026-10-18' ? 7 : 1,
      toFormat: () => date,
      toSeconds: () => Date.parse(date + 'T13:00:00Z') / 1000,
    },
    console: { log() {} },
  });
}
function conversation(id, last = '', sends = 0) {
  return {
    id,
    inbox_id: 2,
    labels: ['seguimiento'],
    last_activity_at: Date.parse('2026-10-19T12:00:00Z') / 1000,
    custom_attributes: {
      seguimiento_ultimo_envio: last,
      seguimiento_envios: sends,
    },
    meta: { assignee: { name: 'Julieta' } },
  };
}
test('second message waits two days, including a Sunday between sends', () => {
  assert.equal(
    classify('2026-10-19', [conversation(1, '2026-10-18', 1)]).length,
    0
  );
  assert.equal(
    classify('2026-10-19', [conversation(1, '2026-10-17', 1)])[0].json.paso,
    2
  );
  assert.equal(
    classify('2026-10-18', [conversation(1, '2026-10-16', 1)]).length,
    0
  );
});
test('today markers, future dates and incomplete legacy markers do not repeat sends', () => {
  ['2026-10-19', '2026-10-20', ''].forEach(date => {
    assert.equal(classify('2026-10-19', [conversation(1, date, 1)]).length, 0);
  });
});
test('400 eligible conversations each produce one next step without recipient truncation', () => {
  const input = Array.from({ length: 400 }, (_, id) => conversation(id + 1));
  const output = classify('2026-10-19', input.concat(input));
  assert.equal(output.length, 400);
  assert.equal(
    new Set(output.map(item => item.json.conversation_id)).size,
    400
  );
  assert.ok(output.every(item => item.json.paso === 1));
});
test('outage advances only the next step, not every missed day', () => {
  const result = classify('2026-10-19', [conversation(1, '2026-10-14', 1)]);
  assert.equal(result.length, 1);
  assert.equal(result[0].json.paso, 2);
});
test('filter resolves the label from configuration after the purchases HTTP response', () => {
  const op = operation('Buscar Chats con Seguimiento', '/jsonBody');
  assert.ok(op, 'builder must fix the HTTP filter context');
  const result = vm.runInNewContext(op.value.slice(3, -2), {
    $json: { purchases: [], config: { enabled: true } },
    $: () => ({
      first: () => ({ json: { label_seguimiento: 'seguimiento' } }),
    }),
  });
  assert.deepEqual(JSON.parse(result).payload[0].values, ['seguimiento']);
});
test('Sunday gate uses configuration instead of the purchases response', () => {
  const op = operation('Hoy Se Manda?', '/conditions/conditions/0/leftValue');
  assert.ok(op, 'builder must fix the day gate context');
  const result = vm.runInNewContext(op.value.slice(3, -2), {
    $json: { purchases: [], config: {} },
    $: () => ({ first: () => ({ json: { dias_sin_envio: '7' } }) }),
    $now: {
      setZone() {
        return this;
      },
      weekday: 7,
    },
  });
  assert.equal(result, false);
});
test('conversation pagination continues past the former 40-page cutoff', () => {
  assert.equal(
    operation(
      'Buscar Chats con Seguimiento',
      '/options/pagination/pagination/limitPagesFetched'
    )?.value,
    false
  );
});
