import test from 'node:test';
import assert from 'node:assert/strict';
import { setLanguage } from '../src/i18n-core.ts';
import {
  activitySummary,
  consolidationLine,
  newConfirmation,
  notice,
  primaryAction,
  trayLook,
} from '../src/menu-model.ts';
import { demoMenuStatus } from '../src/menu-demo.ts';

setLanguage('fr');
const status = (change = {}) => ({ ...demoMenuStatus('idle'), ...change });

test('l’icône pâlit hors connexion ou en pause et porte un halo quand le serveur travaille', () => {
  assert.equal(trayLook(null), 'dim');
  assert.equal(trayLook(status({ connected: false })), 'dim');
  const base = status();
  assert.equal(trayLook({ ...base, pause: { ...base.pause, all: true } }), 'dim');
  assert.equal(trayLook(base), 'idle');
  assert.equal(trayLook({ ...base, activity: { ...base.activity, processing: 2 } }), 'working');
});

test('l’action principale est la pause de toutes les banques, ou le démarrage du serveur local', () => {
  const base = status();
  assert.equal(primaryAction(base).kind, 'pause');
  assert.equal(primaryAction({ ...base, pause: { ...base.pause, all: true } }).kind, 'resume');
  assert.equal(primaryAction({ ...base, consultationOnly: true }).disabled, true);
  const offline = {
    ...base,
    connected: false,
    service: { ...base.service, running: false, canStart: true },
  };
  assert.equal(primaryAction(offline).kind, 'start');
  assert.equal(
    primaryAction({ ...offline, service: { ...offline.service, installed: false } }),
    null,
  );
});

test('le bandeau dit d’abord que le serveur est injoignable, puis la pause et le plafond', () => {
  const base = status();
  assert.equal(notice(base), null);
  assert.equal(notice({ ...base, connected: false }).tone, 'red');
  assert.match(
    notice({ ...base, pause: { ...base.pause, banks: ['notes'] } }).text,
    /En pause\s: Notes personnelles/,
  );
  const capped = {
    ...base,
    usage: { ...base.usage, gauges: [{ ...base.usage.gauges[0], level: 2 }] },
  };
  assert.equal(notice(capped).tone, 'red');
});

test('activité et consolidation en une ligne, dans les mots de l’app', () => {
  const base = status();
  assert.equal(activitySummary(base), 'Au repos');
  assert.equal(
    activitySummary({ ...base, activity: { ...base.activity, processing: 2, pending: 14 } }),
    '2 en cours · 14 en attente',
  );
  const c = base.bankStatus.consolidation;
  assert.equal(
    consolidationLine({ ...c, phase: 'pending', pendingFacts: 236 }).text,
    '236 faits à consolider',
  );
  assert.equal(consolidationLine({ ...c, phase: 'disabled' }).tone, 'neutral');
  assert.equal(consolidationLine(null), null);
});

test('seule une confirmation apparue après une action du volet lui est montrée', () => {
  const window = {
    id: 'fenetre',
    title: 'Supprimer ?',
    message: '',
    confirmTitle: 'Supprimer',
    destructive: true,
  };
  const mine = {
    id: 'volet',
    title: 'Pause ?',
    message: '',
    confirmTitle: 'Pause',
    destructive: false,
  };
  const before = status({ confirmations: [window] });
  assert.equal(newConfirmation(before, status({ confirmations: [window] })), null);
  assert.equal(newConfirmation(before, status({ confirmations: [window, mine] })).id, 'volet');
});
