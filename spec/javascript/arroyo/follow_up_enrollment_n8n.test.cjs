const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {
  buildEnrollmentPatch,
} = require('../../../docs/arroyo/n8n/follow-up-enrollment-build.cjs');

const baseline = () => ({
  id: 'fF0LK453uWJdBHsR',
  active: true,
  versionId: 'published-version',
  activeVersionId: 'published-version',
  activeVersion: { sameAsDraft: true },
  nodes: [
    {
      name: 'Clasificar Seguimiento Diario',
      parameters: {
        jsCode:
          'function commercialTemplate() {}\nfunction classifyCommercial() { return []; }\nconst contextPages = [];\n// Original legacy code remains here',
      },
    },
  ],
});

test('patches only the classifier and atomic completion parameters on the current published version', () => {
  const patch = buildEnrollmentPatch(baseline());
  assert.equal(patch.baseVersionId, 'published-version');
  assert.equal(patch.operations.length, 3);
  assert.ok(patch.operations.every(op => op.type === 'setNodeParameter'));
  const code = patch.operations[0].value;
  assert.match(code, /follow_up\?\.due/);
  assert.ok(code.endsWith('// Original legacy code remains here'));
  assert.ok(
    !patch.operations.some(op =>
      /Postventa|Postventa Cada|Buscar Chats/.test(op.nodeName)
    )
  );
});

test('refuses a draft different from the published version', () => {
  assert.throws(
    () =>
      buildEnrollmentPatch({ ...baseline(), versionId: 'unpublished-draft' }),
    /published/
  );
});

test('preserves legacy closing but routes enrolled opportunities to the atomic backend', () => {
  const patch = buildEnrollmentPatch(baseline());
  const url = patch.operations.find(
    op => op.nodeName === 'Cerrar Secuencia' && op.path === '/url'
  ).value;
  const body = patch.operations.find(
    op => op.nodeName === 'Cerrar Secuencia' && op.path === '/jsonBody'
  ).value;
  function evaluate(expression, enrolled) {
    return vm.runInNewContext(expression.slice(3, -2), {
      $: name =>
        name === 'Config Chatwoot'
          ? {
              first: () => ({
                json: {
                  url_chatwoot: 'https://chat.example/',
                  account_number: 1,
                },
              }),
            }
          : {
              item: {
                json: {
                  conversation_id: 10295,
                  opportunity_reference: enrolled ? 'reference' : null,
                  labels_finales: ['bici'],
                },
              },
            },
    });
  }
  assert.ok(
    evaluate(url, true).endsWith('/arroyo/commercial/follow_up/complete')
  );
  assert.ok(evaluate(url, false).endsWith('/conversations/10295/labels'));
  assert.deepEqual(JSON.parse(evaluate(body, true)), {
    conversation_id: 10295,
    opportunity_reference: 'reference',
  });
  assert.deepEqual(JSON.parse(evaluate(body, false)), { labels: ['bici'] });
});
