import test from 'node:test';
import assert from 'node:assert/strict';
import { modelWorkflowDemo, changeModelWorkflowDemo } from '../src/model-workflow-demo.ts';

const server = (source = 'local') => ({
  ...modelWorkflowDemo(),
  hindsightModels: { decision: source, local: { phase: 'running' } },
});
const change = (data, changes) =>
  changeModelWorkflowDemo(data, 'server.models.prepare', {
    revision: data.modelWorkflow.revision,
    changes,
  });

test('demo cancel restores the source selector and workflow together while retaining local service status', () => {
  const data = server();
  changeModelWorkflowDemo(data, 'server.decision', { source: 'cloud' });
  data.hindsightModels.local.phase = 'stopped';
  changeModelWorkflowDemo(data, 'server.revert', {});
  assert.equal(data.hindsightModels.decision, 'local');
  assert.equal(data.modelWorkflow.decisions.reflect.source, 'local');
  assert.equal(data.hindsightModels.local.phase, 'stopped');
});

test('independent demo servers never reuse another server’s saved model state', () => {
  const first = server('local');
  const second = server('cloud');
  const reflect = second.roles.find((role) => role.id === 'reflect');
  reflect.fields[1].value = 'isolated-model';
  changeModelWorkflowDemo(first, 'server.decision', { source: 'off' });
  changeModelWorkflowDemo(second, 'server.decision', { source: 'off' });
  changeModelWorkflowDemo(second, 'server.revert', {});
  assert.equal(second.hindsightModels.decision, 'cloud');
  assert.equal(
    second.roles.find((role) => role.id === 'reflect').fields[1].value,
    'isolated-model',
  );
});

test('demo confirmation saves the reviewed draft rather than a later edit and expires after use', () => {
  const data = server();
  const name = 'HINDSIGHT_API_REFLECT_USE_DECISION_MODEL';
  change(data, { [name]: 'false' });
  changeModelWorkflowDemo(data, 'server.save', {});
  change(data, { [name]: 'true' });
  changeModelWorkflowDemo(data, 'confirm', { id: 'example-model-save' });
  assert.equal(data.modelWorkflow.values[name], 'false');
  assert.equal(data.needsRestart, true);
  assert.equal(data.hasChanges, false);
  assert.throws(
    () => changeModelWorkflowDemo(data, 'confirm', { id: 'example-model-save' }),
    /expiré/,
  );
  change(data, { [name]: 'true' });
  changeModelWorkflowDemo(data, 'server.revert', {});
  assert.equal(data.modelWorkflow.values[name], 'false');
});
