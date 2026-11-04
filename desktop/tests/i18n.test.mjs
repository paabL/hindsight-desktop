import test from 'node:test';
import assert from 'node:assert/strict';
import { getLanguage, getLocale, setLanguage, translate } from '../src/i18n-core.ts';

test('la langue sélectionnée détermine les libellés et la locale', () => {
  setLanguage('fr');
  assert.equal(getLanguage(), 'fr');
  assert.equal(getLocale(), 'fr-CA');
  assert.equal(translate('Mémoire', 'Memory'), 'Mémoire');
  setLanguage('en');
  assert.equal(getLanguage(), 'en');
  assert.equal(getLocale(), 'en-CA');
  assert.equal(translate('Mémoire', 'Memory'), 'Memory');
});
