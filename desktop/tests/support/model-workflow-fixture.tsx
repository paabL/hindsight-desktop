import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { X } from 'lucide-react';
import { ModelManagement, MemoryDesign, Admin } from '../../src/pages/Manage';
import Sources from '../../src/pages/Sources';
import { ModelWorkflowSettings } from '../../src/components/ModelWorkflow';
import { Button, IconButton, Modal } from '../../src/ui';
import { modelWorkflowDemo } from '../../src/model-workflow-demo';
import { setLanguage } from '../../src/i18n-core';
import '../../src/styles.css';

setLanguage('en');
const P = 'HINDSIGHT_API_';
const fixture: any = ((window as any).modelFixture = {
  calls: [],
  notifications: [],
  delay: 0,
  failure: '',
  applyReplies: true,
  submits: 0,
  completed: 0,
  actions: 0,
});

function serverData() {
  const data: any = {
    ...modelWorkflowDemo(),
    scriptPath: '/fictional/start.sh',
    service: { installed: false },
    hindsightModels: {
      serverIs120: true,
      decision: 'local',
      local: { phase: 'running' },
      cloudConnected: true,
    },
  };
  for (const role of data.roles.filter((r: any) => r.isModelRole)) {
    role.fields.push({
      name: `${P}${role.id === 'default' ? '' : role.id.toUpperCase() + '_'}LLM_BASE_URL`,
      label: 'Endpoint',
      value: '',
    });
  }
  data.roles
    .find((r: any) => r.id === 'decision')
    .fields.push({
      name: P + 'DECISION_MODEL_API_KEY',
      label: 'API key',
      secret: true,
      configured: true,
    });
  return data;
}

function Controls() {
  const [open, setOpen] = useState(false);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        fixture.submits++;
      }}
    >
      <input aria-label="Outside input" />
      <Button onClick={() => fixture.actions++}>Action</Button>
      <IconButton icon={X} label="Icon action" onClick={() => fixture.actions++} />
      <Button disabled onClick={() => fixture.actions++}>
        Disabled action
      </Button>
      <Button>Submit</Button>
      <Button type="submit" onClick={() => fixture.actions++}>
        Explicit submit
      </Button>
      <Button onClick={() => setOpen(true)}>Open dialog</Button>
      {open && (
        <Modal title="Focus fixture" onClose={() => setOpen(false)}>
          <details>
            <summary>Collapsed options</summary>
            <input aria-label="Hidden input" />
          </details>
          <select disabled aria-label="Disabled select">
            <option>Disabled</option>
          </select>
          <textarea disabled aria-label="Disabled text" />
          <input aria-label="Visible input" />
          <Button disabled>Disabled last button</Button>
          <Button onClick={() => setOpen(false)}>Finish</Button>
        </Modal>
      )}
    </form>
  );
}

function Harness({ mode, initial }: { mode: string; initial: any }) {
  const [data, setData] = useState(initial);
  fixture.data = data;
  fixture.update = (patch: any) => setData((old: any) => ({ ...old, ...patch }));
  async function run(command: string, args: any = {}) {
    fixture.calls.push({ command, args: structuredClone(args) });
    const captured = structuredClone(fixture.data);
    if (fixture.delay) await new Promise((resolve) => setTimeout(resolve, fixture.delay));
    fixture.completed++;
    if (fixture.failure === command || fixture.failure === args.name)
      return { error: 'Fixture rejects this change' };
    if (mode === 'models') {
      if (command === 'server.field') {
        for (const role of captured.roles)
          for (const field of role.fields)
            if (field.name === args.name) field.value = field.secret ? null : args.value;
      }
      if (command === 'server.provider') {
        const role = captured.roles.find((r: any) => r.id === args.role);
        role.fields.find((f: any) => f.name.endsWith('_PROVIDER')).value = args.provider;
      }
      if (command === 'server.decision') {
        const fields = captured.roles.find((r: any) => r.id === 'decision').fields;
        fields.find((f: any) => f.name === P + 'DECISION_MODEL_PROVIDER').value = 'hindsight';
        fields.find((f: any) => f.name === P + 'DECISION_MODEL_BASE_URL').value =
          args.source === 'local' ? 'http://127.0.0.1:8766' : '';
      }
      captured.modelWorkflow.revision += '.';
      captured.hasChanges = true;
    }
    if (mode === 'sources' && command === 'folder.choose') {
      captured.open = args.path;
      captured.openKind = 'folder';
    }
    if (mode === 'sources' && command === 'folder.close') {
      captured.open = null;
      captured.openKind = null;
    }
    if (fixture.applyReplies) setData(captured);
    return { data: captured };
  }
  const props = {
    data,
    run,
    busy: false,
    demo: true,
    navigate: () => {},
    refresh: async () => {},
    notify: (text: string) => fixture.notifications.push(text),
  };
  if (mode === 'models') return <ModelManagement {...props} />;
  if (mode === 'memory') return <MemoryDesign {...props} />;
  if (mode === 'admin') return <Admin {...props} />;
  if (mode === 'sources')
    return (
      <Sources
        {...props}
        serverConnected
        banks={[
          { bank_id: 'bank-a', name: 'Bank A' },
          { bank_id: 'bank-b', name: 'Bank B' },
        ]}
        onExploreExample={() => {}}
      />
    );
  if (mode === 'workflow')
    return <ModelWorkflowSettings {...props} configure={() => {}} tools={() => {}} />;
  return <Controls />;
}

const root = createRoot(document.getElementById('root')!);
fixture.mount = (mode: string, overrides: any = {}, key = 'initial') => {
  fixture.calls = [];
  fixture.notifications = [];
  fixture.delay = 0;
  fixture.failure = '';
  fixture.applyReplies = true;
  fixture.submits = 0;
  fixture.completed = 0;
  fixture.actions = 0;
  root.render(<Harness key={key} mode={mode} initial={{ ...serverData(), ...overrides }} />);
};
fixture.mount(new URLSearchParams(location.search).get('mode') || 'models');
