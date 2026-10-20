const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const patch = require('../../../docs/arroyo/n8n/template-only-operations.json');
const baseline = require('../../../docs/arroyo/n8n/post_sale-baseline.json');
const {
  commercialTemplate,
} = require('../../../docs/arroyo/n8n/template-only-build.cjs');

const template = {
  name: 'seg_dia_1',
  status: 'APPROVED',
  language: 'es_AR',
  category: 'MARKETING',
  parameter_format: 'NAMED',
  components: [
    { type: 'BODY', text: 'Texto aprobado: {{asesor}}, {{producto}} 😊' },
  ],
};

test('commercial display and parameters come from the approved Meta template', () => {
  assert.deepEqual(
    commercialTemplate([template], 'seg_dia_1', 'es_AR', {
      asesor: 'Julieta',
      producto: 'una bici',
    }),
    {
      content: 'Texto aprobado: Julieta, una bici 😊',
      name: 'seg_dia_1',
      language: 'es_AR',
      category: 'MARKETING',
      processed_params: { body: { asesor: 'Julieta', producto: 'una bici' } },
    }
  );
});

test('no free-text substitute exists for missing, paused or incompatible templates', () => {
  [
    [],
    [{ ...template, status: 'PAUSED' }],
    [{ ...template, parameter_format: 'POSITIONAL' }],
  ].forEach(templates => {
    assert.throws(
      () =>
        commercialTemplate(templates, 'seg_dia_1', 'es_AR', {
          asesor: 'Julieta',
          producto: 'bici',
        }),
      /seg_dia_1/
    );
  });
  assert.throws(
    () =>
      commercialTemplate([template], 'seg_dia_1', 'es_AR', {
        asesor: '',
        producto: 'bici',
      }),
    /seg_dia_1/
  );
});

test('incremental production patch runs template-only code and preserves daily cadence safeguards', () => {
  assert.equal(patch.operations.length, 4);
  assert.ok(
    patch.operations.every(operation => operation.type === 'setNodeParameter')
  );
  const code = patch.operations.find(
    operation => operation.nodeName === 'Clasificar Seguimiento Diario'
  ).value;
  assert.ok(code.includes('const DIAS_ENTRE_ENVIOS = 2;'));
  assert.ok(!code.includes('FALLBACKS'));
  assert.ok(!code.includes('stage.free_text'));
  const cfg = Object.fromEntries(
    baseline.commercialAssignments.map(item => [item.name, item.value])
  );
  const page = {
    config: { enabled: true, commercial_templates: { 2: [template] } },
    purchases: [],
  };
  const conversation = {
    id: 8,
    inbox_id: 2,
    labels: ['seguimiento'],
    last_activity_at: Date.parse('2026-10-20T12:00:00Z') / 1000,
    meta: { assignee: { name: 'Julieta' } },
  };
  const result = vm.runInNewContext('(function(){' + code + '\n})()', {
    $: name =>
      name === 'Config Chatwoot'
        ? { first: () => ({ json: cfg }) }
        : { first: () => ({ json: page }), all: () => [{ json: page }] },
    $input: { all: () => [{ json: { payload: [conversation] } }] },
    $now: {
      setZone() {
        return this;
      },
      weekday: 2,
      toFormat: () => '2026-10-20',
      toSeconds: () => Date.parse('2026-10-20T13:00:00Z') / 1000,
    },
    console: { log() {} },
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].json.template_name, 'seg_dia_1');
  assert.equal(
    result[0].json.template_content,
    'Texto aprobado: Juli, lo que estabas viendo 😊'
  );
  assert.equal(result[0].json.processed_params.body.asesor, 'Juli');
  patch.operations
    .filter(operation => operation.path === '/jsCode')
    .forEach(operation => {
      assert.ok(!operation.value.includes('stage.free_text'));
    });
});
