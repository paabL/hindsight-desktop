import test from 'node:test';
import assert from 'node:assert/strict';
import { getLanguage, getLocale, setLanguage, translate } from '../src/i18n-core.ts';

test('English is the default without an explicit preference', () => {
  assert.equal(getLanguage(), 'en');
  assert.equal(getLocale(), 'en-CA');
});

test('the explicit language choice controls labels and locale', () => {
  setLanguage('fr');
  assert.equal(getLanguage(), 'fr');
  assert.equal(getLocale(), 'fr-CA');
  assert.equal(translate('Mémoire', 'Memory'), 'Mémoire');
  setLanguage('en');
  assert.equal(getLanguage(), 'en');
  assert.equal(getLocale(), 'en-CA');
  assert.equal(translate('Mémoire', 'Memory'), 'Memory');
});
