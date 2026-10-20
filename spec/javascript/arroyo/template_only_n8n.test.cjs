const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  dueMessages,
} = require('../../../docs/arroyo/n8n/post_sale-transform.cjs');

test('post-sale delegates template selection to Chatwoot regardless of the reply window', () => {
  [true, false].forEach(canReply => {
    const purchase = {
      reference: 'sale',
      revision: 1,
      planned_revision: 1,
      conversation_id: 7,
      can_reply: canReply,
      contact: { name: 'Ana' },
      seller: { name: 'Julieta' },
      product: 'bicicleta',
      inbox: { message_templates: [] },
      follow_ups: [
        {
          id: 3,
          stage: 'd1',
          status: 'scheduled',
          scheduled_at: '2026-10-20T13:00:00Z',
        },
      ],
    };
    const config = {
      enabled: true,
      delivery_timeout_hours: 6,
      stages: { d1: { free_text: 'Editable', template: 'postventa_d1' } },
    };
    assert.deepEqual(
      dueMessages(purchase, config, '2026-10-20T13:00:00Z', 'run')[0].body,
      { revision: 1, execution_id: 'run' }
    );
  });
});
