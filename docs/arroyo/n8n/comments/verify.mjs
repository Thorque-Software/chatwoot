import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Executes only the pure Code-node bodies from the checked-in SDK definitions.
// No external requests or workflow activation; credentials are never loaded.
const source = name => readFileSync(new URL(name, import.meta.url), 'utf8');
const body = (name, id) => {
  const line = source(name).split('\n').find(value => value.startsWith(`const ${id}=`) || value.startsWith(`const ${id} =`));
  assert.ok(line, `Missing node ${id}`);
  return JSON.parse(line.match(/"jsCode":("(?:[^"\\]|\\.)*")/)[1]);
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = (file, id, input, upstream = {}, context = {}) => new AsyncFunction('$input', '$', body(file, id)).call(
  context, { first: () => ({ json: input }), all: () => [{ json: input }] },
  () => ({ first: () => ({ json: upstream }) })
);

const raw = Buffer.from('{ "object": "instagram", "entry": [] }\n');
const encoded = await run('webhook.sdk.js', 'raw', { headers: { 'x-hub-signature-256': 'fixture-signature' } }, {},
  { helpers: { getBinaryDataBuffer: async () => raw } });
assert.deepEqual(Buffer.from(encoded[0].json.payload_base64, 'base64'), raw);
assert.equal(encoded[0].json.signature, 'fixture-signature');

const reply = { id: 1, claim_token: 'fixture-claim' };
let output = await run('process.sdk.js', 'success', { id: '17800000002' }, reply);
assert.equal(output[0].json.status, 'published');
assert.equal(output[0].json.claim_token, reply.claim_token);
output = await run('process.sdk.js', 'success', {}, reply);
assert.equal(output[0].json.status, 'unconfirmed');
assert.equal(output[0].json.remote_reply_id, null);
output = await run('process.sdk.js', 'failure', { error: { httpCode: 403, message: 'sensitive-provider-details' } }, reply);
assert.equal(output[0].json.status, 'failed');
assert.ok(!JSON.stringify(output).includes('sensitive-provider-details'));
for (const code of [0, 408, 500]) {
  output = await run('process.sdk.js', 'failure', { error: { httpCode: code } }, reply);
  assert.equal(output[0].json.status, 'unconfirmed');
}
assert.deepEqual(await run('webhook.sdk.js', 'posts', {}, { statusCode: 403, body: { posts: [{ media_id: '123' }] } }), []);
assert.deepEqual(await run('worker.sdk.js', 'items', { replies: [] }), []);
const claims = await run('worker.sdk.js', 'items', { replies: [reply] });
assert.equal(claims.length, 1);
assert.equal(claims[0].json.operation, 'reply');
assert.deepEqual(await run('process.sdk.js', 'link', {}, { api_version: 'v25.0' }), []);
console.log('Comments workflow logic verified: raw bytes, acknowledgments, uncertain outcomes, redacted errors, rejected input and empty queue.');
