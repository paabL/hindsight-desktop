import test from 'node:test';
import assert from 'node:assert/strict';
import { setLanguage } from '../src/i18n-core.ts';
import {
  localizeConfirmation,
  localizeNativeSnapshot,
  nativeSystemMessage,
} from '../src/native-messages.ts';

const confirmation = (extra = {}) => ({
  id: 'one',
  title: 'Supprimer définitivement la banque « mémoire-équipe » ?',
  message:
    "Faits, documents, entités, observations, configuration : tout est supprimé, sans retour possible. Exportez-la d'abord.",
  confirmTitle: 'Supprimer la banque',
  destructive: true,
  requiredText: 'mémoire-équipe',
  ...extra,
});

test('une suppression explique ses conséquences en anglais sans changer le texte de validation', () => {
  setLanguage('en');
  const result = localizeConfirmation(confirmation());
  assert.equal(result.title, 'Permanently delete memory bank “mémoire-équipe”?');
  assert.match(result.message, /permanently deleted/);
  assert.match(result.message, /Export the memory bank first/);
  assert.equal(result.confirmTitle, 'Delete memory bank');
  assert.equal(result.requiredText, 'mémoire-équipe');
  assert.equal(result.id, 'one');
  assert.equal(result.destructive, true);
});

test('les détails de coût sont traduits et la question utilisateur reste strictement inchangée', () => {
  setLanguage('en');
  const query = 'Créer une banque ?\n\nNe pas modifier ce texte : Estimation : ≈ 3 jetons LLM.';
  const result = localizeConfirmation(
    confirmation({
      title: 'Interroger la mémoire ?',
      message:
        "Le modèle rédigera une réponse à partir des faits de cette banque.\n\nEstimation : ≈ 4 k–9 k jetons LLM, pris sur l'abonnement — valeurs par défaut (aucune trace récente).\n\n" +
        query,
      confirmTitle: 'Générer la réponse',
      requiredText: undefined,
      destructive: false,
    }),
  );
  assert.match(result.message, /Estimate: ≈ 4 k–9 k LLM tokens, uses subscription quota/);
  assert.ok(result.message.endsWith('\n\n' + query));
});

test('le texte d’une directive reste intact même s’il ressemble exactement à un message système', () => {
  setLanguage('en');
  const original = confirmation({
    title: 'Supprimer la directive « Exemple » ?',
    message: 'Son contenu et son historique sont supprimés.',
  });
  const result = localizeConfirmation(original);
  assert.equal(result.title, 'Delete directive “Exemple”?');
  assert.equal(result.message, original.message);
});

test('la localisation du pont préserve les documents, faits et données de la banque sans mutation', () => {
  setLanguage('en');
  const data = {
    title: 'Supprimer la banque',
    text: 'Banque supprimée.',
    documents: [{ title: 'Enregistrer', text: 'Serveur arrêté.' }],
    facts: [{ text: 'Réponse non HTTP' }],
    error: 'Banque inconnue.',
  };
  const snapshot = {
    app: {
      connected: false,
      bank: null,
      banks: [],
      serverURL: 'http://127.0.0.1:8888',
      connectionError: 'Serveur injoignable : connection refused',
    },
    section: 'documents',
    data,
    confirmations: [confirmation()],
    messages: ['Banque supprimée.'],
  };
  const result = localizeNativeSnapshot(snapshot);
  assert.equal(result.data.title, data.title);
  assert.equal(result.data.text, data.text);
  assert.strictEqual(result.data.documents, data.documents);
  assert.strictEqual(result.data.facts, data.facts);
  assert.equal(result.data.error, 'Unknown memory bank.');
  assert.equal(result.app.connectionError, 'Server unreachable: connection refused');
  assert.equal(result.messages[0], 'Memory bank deleted.');
  assert.equal(snapshot.data.error, 'Banque inconnue.');
  setLanguage('fr');
  assert.strictEqual(localizeNativeSnapshot(snapshot), snapshot);
});

test('un message inconnu reste visible dans sa forme d’origine', () => {
  setLanguage('en');
  const unknown = 'Message personnalisé envoyé par mon serveur';
  assert.equal(nativeSystemMessage(unknown), unknown);
});
