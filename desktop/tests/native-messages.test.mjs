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
      title: 'Obtenir une réponse ?',
      message:
        "Le modèle rédigera une réponse à partir des faits de cette banque.\n\nEstimation : ≈ 4 k–9 k jetons LLM, pris sur l'abonnement — valeurs par défaut (aucune trace récente).\n\n" +
        query,
      confirmTitle: 'Obtenir la réponse',
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
      'Fusion terminée (3 documents ajoutés, 1 234 faits, 1 document ignoré) ; « brouillon » supprimée.',
    ),
    'Merge complete (3 documents added, 1 234 facts, 1 skipped document); “brouillon” deleted.',
  );
  assert.equal(
    nativeSystemMessage(
      'Fusion terminée (1 document ajouté). 12 faits attendent la consolidation de « équipe » : lancez-la depuis « Mémoire › Consolidation ».',
    ),
    'Merge complete (1 document added). 12 facts are waiting for consolidation in “équipe”. Run it from Memory › Consolidation.',
  );
  assert.equal(
    nativeSystemMessage(
      "Fusion terminée (2 documents ajoutés, 1 document ignoré). « brouillon » est CONSERVÉE : 1 document ignoré n'existe que dans la source. Vérifiez, puis supprimez-la depuis « Réglages › Banque ».",
    ),
    'Merge complete (2 documents added, 1 skipped document). “brouillon” was KEPT: 1 skipped document exists only in the source. Check, then delete it from Settings › Memory bank.',
  );
  assert.equal(
    nativeSystemMessage('« équipe » est en pause. 2 régénérations de connaissances annulées.'),
    '“équipe” is paused. 2 knowledge regenerations cancelled.',
  );
  assert.equal(nativeSystemMessage('1 fait effacé.'), '1 fact cleared.');
  assert.equal(nativeSystemMessage('1 234 observations effacées.'), '1 234 observations cleared.');
  assert.equal(
    nativeSystemMessage('3 sources envoyées ; traitement à suivre dans cette liste.'),
    '3 sources uploaded. Follow processing in this list.',
  );
  assert.equal(
    nativeSystemMessage(
      "L'opération n'est pas encore terminée ; suivez-la dans « Activité › Traitements ».",
    ),
    'The operation has not finished yet. Follow it in Activity › Processing.',
  );
  assert.equal(
    nativeSystemMessage("L'opération a échoué : archive invalide"),
    'The operation failed: archive invalide',
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

test('la consolidation dit en anglais ce qu’elle traitera, et pourquoi elle est refusée', () => {
  setLanguage('en');
  const request = localizeConfirmation(
    confirmation({
      title: 'Consolider les faits ?',
      message:
        "Le serveur va créer ou mettre à jour les observations à partir des 27 619 faits pas encore consolidés. Cela appelle le LLM de consolidation. Chaque fait rejoint les observations de sa portée (celle de son document).\n\nEstimation : ≈ 6,2 M–24,9 M jetons LLM, pris sur l'abonnement (≈ 21 $ à l'usage) — valeurs par défaut (aucune trace récente).",
      confirmTitle: 'Consolider',
      destructive: false,
      requiredText: undefined,
    }),
  );
  assert.equal(request.title, 'Consolidate facts?');
  assert.equal(request.confirmTitle, 'Consolidate');
  assert.match(
    request.message,
    /^The server will create or update observations from the 27 619 facts not yet consolidated\./,
  );
  assert.match(request.message, /Estimate: ≈ 6,2 M–24,9 M LLM tokens, uses subscription quota/);
  const single = localizeConfirmation(
    confirmation({
      title: 'Consolider les faits ?',
      message:
        'Le serveur va créer ou mettre à jour les observations à partir du seul fait pas encore consolidé. Cela appelle le LLM de consolidation. Chaque fait rejoint les observations de sa portée (celle de son document).',
    }),
  );
  assert.match(
    single.message,
    /^The server will create or update observations from the only fact not yet consolidated\./,
  );
  const recover = localizeConfirmation(
    confirmation({
      title: 'Reconsolider les faits en échec ?',
      message:
        "Les 3 faits en échec de consolidation seront remis dans la file. Aucune observation n'est supprimée.",
      confirmTitle: 'Reconsolider',
    }),
  );
  assert.equal(recover.title, 'Reconsolidate failed facts?');
  assert.equal(
    recover.message,
    'The 3 facts that failed consolidation will be requeued. No observations are deleted.',
  );
  assert.equal(recover.confirmTitle, 'Reconsolidate');
  for (const [french, english] of [
    [
      "La consolidation est désactivée pour cette banque : le serveur ne crée pas d'observations. Activez « Créer des observations » dans « Réglages › Comportement de la mémoire › Consolidation ».",
      'Consolidation is turned off for this memory bank: the server does not create observations. Turn on “Create observations” in Settings › Memory behavior › Consolidation.',
    ],
    [
      'Une consolidation est déjà en cours pour cette banque.',
      'A consolidation is already running for this memory bank.',
    ],
    ['Consolidation mise en file.', 'Consolidation queued.'],
    ['1 fait remis en file.', '1 fact requeued.'],
    ['12 faits remis en file.', '12 facts requeued.'],
  ])
    assert.equal(nativeSystemMessage(french), english);
  setLanguage('fr');
});

test('les erreurs du service, des mises à jour, des dossiers et du journal d’accès sont traduites', () => {
  setLanguage('en');
  for (const [french, english] of [
    [
      "Installation impossible : Le script a changé pendant l'installation : vérifiez-le à nouveau.",
      'Installation failed: The script changed during installation. Review it again.',
    ],
    ['Arrêt impossible : boom', 'Stop failed: boom'],
    ["Le service ne s'est pas arrêté dans les 30 s.", 'The service did not stop within 30 s.'],
    [
      "Le service a été lancé mais l'API ne répond pas (code de sortie 1). Consultez le journal ci-dessous.",
      'The service was started but the API does not respond (exit code 1). See the log below.',
    ],
    ['git fetch a échoué : refus', 'git fetch failed: refus'],
    [
      'La compilation a échoué (code 2) : voir le journal.',
      'The build failed (code 2). See the log.',
    ],
    [
      'Application construite invalide : identifiant « a.b » au lieu de « c.d »',
      'Invalid built app: identifier “a.b” instead of “c.d”',
    ],
    ["/x/run.sh n'est pas exécutable (chmod u+x).", '/x/run.sh is not executable (chmod u+x).'],
    ['Vérification : échec (code 1). Voir le journal.', 'Check: failed (code 1). See the log.'],
    [
      'Traces illisibles pour demo : Serveur injoignable : délai',
      'Unreadable traces for demo: Server unreachable: délai',
    ],
    ['repo : git ls-files a échoué : fatal', 'repo: git ls-files failed: fatal'],
    [
      'Réponse inattendue pour /v1/x : champ manquant « id » à .items[0]',
      'Unexpected response for /v1/x: missing field “id” at .items[0]',
    ],
    ['mcp · client non identifié (profil 3fa2)', 'mcp · unidentified client (profile 3fa2)'],
    ['http · appelant non identifié', 'http · unidentified caller'],
    [
      '1 source envoyée ; traitement à suivre dans cette liste.',
      '1 source uploaded. Follow processing in this list.',
    ],
    ['Relance : 2 sur 5…', 'Retrying: 2 of 5…'],
  ])
    assert.equal(nativeSystemMessage(french), english);
  // Le nombre capturé n'apporte jamais d'espace en trop.
  assert.equal(
    localizeConfirmation(
      confirmation({
        title: 'Appliquer le gabarit à « demo » ?',
        message: 'Effet prévu : 1 modèle mental créé, 3 directives mises à jour.',
        confirmTitle: 'Appliquer le gabarit',
        requiredText: undefined,
        destructive: false,
      }),
    ).message,
    'Expected effect: 1 mental model created, 3 directives updated.',
  );
  setLanguage('fr');
});
