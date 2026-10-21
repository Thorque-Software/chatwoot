const fs = require('node:fs');
const path = require('node:path');
const {
  classifyCommercial,
  completionParameters,
} = require('./commercial-funnel-build.cjs');

function buildEnrollmentPatch(workflow) {
  if (
    !workflow.active ||
    workflow.versionId !== workflow.activeVersionId ||
    !workflow.activeVersion?.sameAsDraft
  ) {
    throw new Error(
      'Read the current published version with no unpublished draft before preparing this patch'
    );
  }
  const original = workflow.nodes.find(
    node => node.name === 'Clasificar Seguimiento Diario'
  )?.parameters.jsCode;
  const start = original?.indexOf('function classifyCommercial(');
  const end = original?.indexOf('const contextPages =');
  if (start < 0 || end < start || start === undefined)
    throw new Error('Published classifier changed; review before patching');
  const jsCode =
    original.slice(0, start) +
    classifyCommercial.toString() +
    '\n' +
    original.slice(end);
  const close = completionParameters();
  return {
    workflowId: workflow.id,
    baseVersionId: workflow.activeVersionId,
    operations: [
      {
        type: 'setNodeParameter',
        nodeName: 'Clasificar Seguimiento Diario',
        path: '/jsCode',
        value: jsCode,
      },
      {
        type: 'setNodeParameter',
        nodeName: 'Cerrar Secuencia',
        path: '/url',
        value: close.url,
      },
      {
        type: 'setNodeParameter',
        nodeName: 'Cerrar Secuencia',
        path: '/jsonBody',
        value: close.jsonBody,
      },
    ],
  };
}

if (require.main === module) {
  const workflow = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const patch = buildEnrollmentPatch(workflow);
  fs.writeFileSync(
    path.join(__dirname, 'follow-up-enrollment-operations.json'),
    JSON.stringify(patch, null, 2) + '\n'
  );
  process.stdout.write(
    JSON.stringify({
      workflowId: patch.workflowId,
      baseVersionId: patch.baseVersionId,
      operations: patch.operations.length,
    }) + '\n'
  );
}

module.exports = { buildEnrollmentPatch };
