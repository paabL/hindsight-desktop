import test from 'node:test';
import assert from 'node:assert/strict';
import { setLanguage } from '../src/i18n-core.ts';
import { exampleText, localizeExample, startExampleContent } from '../src/demo-en.ts';

test('l’exemple ouvert en anglais l’est en entier, et garde sa langue ensuite', () => {
  setLanguage('en');
  startExampleContent();
  assert.equal(exampleText('Projet Horizon'), 'Horizon Project');
  assert.equal(
    exampleText('Les liens de mémoire dans cet exemple.'),
    'Links for memory in this example.',
  );
  // Libellé tronqué d’un fait : même début traduit.
  const fact =
    'Les sources sont collectées dans une archive commune avant tout traitement par Hindsight.';
  assert.equal(
    exampleText(fact.slice(0, 60)),
    'Sources are collected into a shared archive before any proce',
  );
  // Les clés, identifiants et chemins ne sont jamais touchés.
  assert.deepEqual(
    localizeExample({ id: 'example-0', path: '/Exemple/horizon-app', tags: ['projet:horizon'] }),
    { id: 'example-0', path: '/Exemple/horizon-app', tags: ['projet:horizon'] },
  );
  // Comme pour une vraie banque, changer de langue ne traduit pas les documents déjà ouverts.
  setLanguage('fr');
  assert.equal(exampleText('Projet Horizon'), 'Horizon Project');
  startExampleContent();
  assert.equal(exampleText('Projet Horizon'), 'Projet Horizon');
});
