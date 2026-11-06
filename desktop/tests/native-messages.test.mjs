import test from 'node:test';
import assert from 'node:assert/strict';
import { setLanguage } from '../src/i18n-core.ts';
import {
  localizeConfirmation,
  localizeNativeSnapshot,
  nativeSourceReason,
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

test('une interruption du moteur explique la récupération dans la langue choisie', () => {
  const message =
    "Le moteur Hindsight s'est interrompu. Vérifiez « Activité › Traitements » avant de réessayer, puis reconnectez le serveur.";
  setLanguage('en');
  assert.equal(
    nativeSystemMessage(message),
    'The Hindsight engine stopped. Check Activity › Processing before trying again, then reconnect the server.',
  );
  setLanguage('fr');
  assert.equal(nativeSystemMessage(message), message);
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

test('les messages d’état composés du moteur sont traduits sans toucher aux noms capturés', () => {
  setLanguage('en');
  assert.equal(
    nativeSystemMessage('Banque renommée « Projet Été ».'),
    'Memory bank renamed “Projet Été”.',
  );
  assert.equal(
    nativeSystemMessage('Choisissez deux banques différentes.'),
    'Choose two different memory banks.',
  );
  assert.equal(
    nativeSystemMessage(
      'Fusion terminée (documents_imported 3) ; « brouillon » supprimée. Lancez la consolidation de « équipe » pour intégrer les nouveaux faits aux observations.',
    ),
    'Merge complete (documents_imported 3); “brouillon” deleted. Run consolidation on “équipe” to add the new facts to its observations.',
  );
  assert.equal(
    nativeSystemMessage('« équipe » est en pause. 2 régénérations de connaissances annulées.'),
    '“équipe” is paused. 2 knowledge regenerations cancelled.',
  );
  assert.equal(nativeSystemMessage('1 fait(s) supprimé(s).'), '1 fact deleted.');
  assert.equal(
    nativeSystemMessage('3 sources envoyées ; traitement à suivre dans cette liste.'),
    '3 sources uploaded. Follow processing in this list.',
  );
  assert.equal(
    nativeSystemMessage(
      "L'opération op-7 n'est pas terminée ; suivez-la dans « Activité › Traitements ».",
    ),
    'Operation op-7 is not finished yet. Follow it in Activity › Processing.',
  );
  // Préfixe générique : une règle plus précise passe avant « Échec : … ».
  assert.equal(
    nativeSystemMessage("Échec : HTTP 500. Vérifiez l'état des deux banques avant de recommencer."),
    'Failed: HTTP 500. Check both memory banks before trying again.',
  );
  setLanguage('fr');
  assert.equal(
    nativeSystemMessage('Choisissez deux banques différentes.'),
    'Choisissez deux banques différentes.',
  );
});

test('les raisons par source du catalogue se traduisent à l’affichage', () => {
  setLanguage('en');
  assert.equal(nativeSourceReason('En attente de revue'), 'Pending review');
  assert.equal(nativeSourceReason('Source locale indisponible.'), 'Local source unavailable.');
  assert.equal(
    nativeSourceReason(
      'Ce dossier est rattaché à la banque « équipe ». Sélectionnez-la pour envoyer ou retirer ses sources.',
    ),
    'This folder belongs to the “équipe” memory bank. Select it to upload or remove its sources.',
  );
  assert.equal(nativeSourceReason('Raison écrite à la main'), 'Raison écrite à la main');
  assert.equal(nativeSourceReason(undefined), '');
  setLanguage('fr');
  assert.equal(nativeSourceReason('En attente de revue'), 'En attente de revue');
});

test('les erreurs secondaires des sections et les pages de connaissance sont traduites', () => {
  setLanguage('en');
  const result = localizeNativeSnapshot({
    app: { connected: true, bank: 'b', banks: [], serverURL: 'http://127.0.0.1:8888' },
    section: 'dashboard',
    data: {
      partialErrors: ['entités : HTTP 500'],
      modelError: 'Connaissance inconnue.',
      detailError: 'Banque inconnue.',
    },
    confirmations: [
      confirmation({
        title: 'Supprimer la page de connaissance « Projet » ?',
        message: 'Son contenu et son historique sont supprimés.',
        confirmTitle: 'Supprimer',
        requiredText: null,
      }),
    ],
    messages: ['Page de connaissance supprimée.'],
  });
  assert.deepEqual(result.data.partialErrors, ['entities: HTTP 500']);
  assert.equal(result.data.modelError, 'Unknown knowledge item.');
  assert.equal(result.data.detailError, 'Unknown memory bank.');
  assert.equal(result.confirmations[0].title, 'Delete knowledge page “Projet”?');
  assert.equal(result.messages[0], 'Knowledge page deleted.');
});
