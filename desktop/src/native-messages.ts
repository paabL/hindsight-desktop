import { getLanguage } from './i18n-core.ts';
import { advancedConfirmationMessage } from './native-confirmations.ts';
import { nativeCatalogText, nativeRoleEffective } from './native-catalog.ts';
import type { Confirmation, Row, Snapshot } from './types';

// Seuls les champs système du pont sont localisés. Le contenu des documents, les noms,
// les requêtes, les identifiants et le texte à retaper restent intacts.
const exact: Record<string, string> = {
  "Le moteur Hindsight s'est interrompu. Vérifiez les opérations avant de réessayer, puis reconnectez le serveur.":
    'The Hindsight engine stopped. Check operations before trying again, then reconnect the server.',
  'Actualisez la liste des sources.': 'Refresh the source list.',
  'Catalogue de sources incomplet ; actualisez la liste.':
    'The source catalog is incomplete. Refresh the list.',
  'Une collecte est en cours dans ce dossier.': 'A collection is in progress in this folder.',
  'Source modifiée pendant sa lecture ; actualisez la vue.':
    'The source changed while it was being read. Refresh the view.',
  'Les sources ont changé ; préparez un nouvel aperçu.':
    'The sources changed. Prepare a new preview.',
  'Réglages des modèles invalides.': 'Invalid model settings.',
  'Serveur Hindsight 1.2.0 requis pour ces réglages de décision.':
    'Hindsight server 1.2.0 is required for these decision settings.',
  'Les réglages ont changé. Actualisez avant de réessayer.':
    'Settings have changed. Refresh before trying again.',
  'Ce réglage doit être modifié dans les options avancées.':
    'This setting must be changed in advanced options.',
  "Valeur d'activation invalide.": 'Invalid activation value.',
  'Fournisseur de décision inconnu.': 'Unknown decision provider.',
  'Nom de modèle invalide.': 'Invalid model name.',
  "L'adresse du serveur enregistrée a été refusée. Vérifiez son adresse dans les réglages ; le serveur local est utilisé en attendant.":
    'The saved server address was rejected. Check it in Settings; the local server is used in the meantime.',
  Créer: 'Create',
  Appliquer: 'Apply',
  Enregistrer: 'Save',
  Supprimer: 'Delete',
  'Supprimer la banque': 'Delete memory bank',
  Retirer: 'Remove',
  Réinitialiser: 'Reset',
  Effacer: 'Clear',
  'Effacer les observations': 'Clear observations',
  Rétablir: 'Restore',
  Invalider: 'Invalidate',
  Retraiter: 'Reprocess',
  Rafraîchir: 'Refresh',
  Cloner: 'Clone',
  Fusionner: 'Merge',
  Restaurer: 'Restore',
  Envoyer: 'Send',
  Importer: 'Import',
  Ajouter: 'Add',
  Collecter: 'Collect',
  Renommer: 'Rename',
  "Changer l'identifiant": 'Change identifier',
  'Changer la portée': 'Change scope',
  Lancer: 'Start',
  'Lancer maintenant': 'Run now',
  Relancer: 'Retry',
  'Tout relancer': 'Retry all',
  "Annuler l'opération": 'Cancel operation',
  'Remettre en file': 'Requeue',
  'Mettre en pause': 'Pause',
  Reprendre: 'Resume',
  'Geler la file': 'Freeze queue',
  'Reprendre la file': 'Resume queue',
  'Vider la file': 'Clear queue',
  'Annuler les doublons': 'Cancel duplicates',
  Installer: 'Install',
  Désinstaller: 'Uninstall',
  'Installer et démarrer': 'Install and start',
  Arrêter: 'Stop',
  Redémarrer: 'Restart',
  'Approuver et redémarrer': 'Approve and restart',
  'Approuver et démarrer': 'Approve and start',
  'Se connecter': 'Connect',
  'Se déconnecter': 'Disconnect',
  Activer: 'Enable',
  Désactiver: 'Disable',
  'Mettre à jour': 'Update',
  Recompiler: 'Rebuild',
  'Mettre de côté et mettre à jour': 'Set aside and update',
  'Générer la réponse': 'Generate answer',
  'Vérifier les quotas': 'Check quotas',
  'Tester les modèles': 'Test models',
  'Vérifier / reprendre': 'Check / resume',
  "Lancer l'essai": 'Run preview',
  'Interroger la mémoire ?': 'Ask memory?',
  'Envoyer les sources à Hindsight ?': 'Send sources to Hindsight?',
  'Vérifier ou reprendre l’envoi initial ?': 'Check or resume the original upload?',
  'Retirer de la mémoire ?': 'Remove from memory?',
  'Collecter les sources ?': 'Collect sources?',
  'Modifier les tags du document ?': 'Change document tags?',
  'Retraiter ce document ?': 'Reprocess this document?',
  'Supprimer définitivement ce document ?': 'Permanently delete this document?',
  'Corriger ce fait ?': 'Edit this fact?',
  'Invalider ce fait ?': 'Invalidate this fact?',
  'Rétablir ce fait ?': 'Restore this fact?',
  'Effacer les observations issues de ce fait ?': 'Clear observations derived from this fact?',
  "Restaurer l'archive dans une nouvelle banque ?": 'Restore the archive into a new memory bank?',
  'Enregistrer la structure de la mémoire ?': 'Save memory structure?',
  'Revenir à la configuration du serveur ?': 'Reset to the server configuration?',
  "Essai à blanc de l'extraction ?": 'Preview extraction?',
  'Relancer cette opération ?': 'Retry this operation?',
  'Lancer cette opération maintenant ?': 'Run this operation now?',
  'Annuler cette opération ?': 'Cancel this operation?',
  'Supprimer cette entrée ?': 'Delete this history entry?',
  'Lancer la consolidation ?': 'Start consolidation?',
  'Réessayer les faits en échec de consolidation ?': 'Retry facts that failed consolidation?',
  'Mettre les traitements en pause ?': 'Pause processing?',
  'Reprendre les traitements ?': 'Resume processing?',
  'Enregistrer les plafonds ?': 'Save limits?',
  'Modifier la grille tarifaire ?': 'Change the price list?',
  'Geler la file du serveur ?': 'Freeze the server queue?',
  'Reprendre la file du serveur ?': 'Resume the server queue?',
  "Vérifier les quotas d'abonnement ?": 'Check subscription quotas?',
  'Tester les modèles du serveur ?': 'Test server models?',
  'Enregistrer le script de lancement ?': 'Save the launch script?',
  'Installer le service Hindsight ?': 'Install the Hindsight service?',
  'Réinstaller le service Hindsight ?': 'Reinstall the Hindsight service?',
  'Désinstaller le service Hindsight ?': 'Uninstall the Hindsight service?',
  'Le script de lancement a changé': 'The launch script has changed',
  'Arrêter le serveur Hindsight ?': 'Stop the Hindsight server?',
  'Redémarrer le serveur Hindsight ?': 'Restart the Hindsight server?',
  'Installer le modèle de décision sur ce Mac ?': 'Install the decision model on this Mac?',
  'Arrêter le modèle de décision local ?': 'Stop the local decision model?',
  'Désinstaller le modèle de décision local ?': 'Uninstall the local decision model?',
  'Installer la mise à jour ?': 'Install the update?',
  "Recompiler l'app ?": 'Rebuild the app?',
  'Requête invalide.': 'Invalid request.',
  'Connectez le serveur et choisissez une banque.': 'Connect the server and select a memory bank.',
  'Adresse invalide.': 'Invalid address.',
  'Une mise à jour est en cours.': 'An update is in progress.',
  'Seules les URL http:// et https:// sont acceptées.':
    'Only http:// and https:// URLs are supported.',
  "N'incluez pas d'identifiants dans l'URL : ils seraient enregistrés en clair dans les préférences.":
    'Do not include credentials in the URL: they would be saved as plain text in preferences.',
  "L'adresse du serveur ne doit contenir ni paramètres ni fragment.":
    'The server address must not include query parameters or a fragment.',
  "URL sans nom d'hôte.": 'URL has no host name.',
  'Connexion HTTP non chiffrée sur le réseau local : le contenu des banques y circule en clair. Préférez HTTPS ou un tunnel SSH.':
    'Unencrypted HTTP connection on the local network: memory bank content is sent as plain text. Use HTTPS or an SSH tunnel when possible.',
  'HTTP non chiffré vers Internet refusé : utilisez https:// (ou un tunnel SSH vers 127.0.0.1).':
    'Unencrypted HTTP connections over the internet are not allowed. Use https:// or an SSH tunnel to 127.0.0.1.',
  'Aucune mise à jour installée à relancer.': 'No installed update is ready to relaunch.',
  'Banque inconnue.': 'Unknown memory bank.',
  'Choisissez un dossier absolu.': 'Choose an absolute folder path.',
  'Format de document non autorisé.': 'Document format is not allowed.',
  'Lien non autorisé.': 'Link is not allowed.',
  'Entité inconnue ; rechargez les filtres.': 'Unknown entity; reload the filters.',
  'Pièce jointe inconnue.': 'Unknown attachment.',
  'Cette pièce jointe dépasse 12 Mo.': 'This attachment exceeds 12 MB.',
  'Synthèse inconnue.': 'Unknown summary.',
  'Opération inconnue.': 'Unknown operation.',
  'Directive inconnue.': 'Unknown directive.',
  'Les plafonds doivent être des montants positifs valides.':
    'Limits must be valid positive amounts.',
  'Valeur invalide.': 'Invalid value.',
  'Export impossible.': 'Export failed.',
  'Archive invalide.': 'Invalid archive.',
  'Modèle invalide.': 'Invalid template.',
  'Ce nœud ne fait pas partie du graphe chargé.': 'This node is not in the loaded graph.',
  'Nom de réglage Hindsight invalide.': 'Invalid Hindsight setting name.',
  'Nom de variable invalide.': 'Invalid variable name.',
  'Serveur Hindsight 1.2.0 requis pour les modèles Hindsight.':
    'Hindsight models require Hindsight server 1.2.0.',
  "Installez et démarrez d'abord le modèle de décision sur ce Mac.":
    'Install and start the decision model on this Mac first.',
  'Choix inconnu.': 'Unknown option.',
  'Sauvegarde inconnue.': 'Unknown backup.',
  'Compte inconnu.': 'Unknown account.',
  'Dossier inconnu.': 'Unknown folder.',
  'Section inconnue.': 'Unknown section.',
  'Cette confirmation a expiré ou le texte saisi ne correspond pas.':
    'This confirmation expired or the text you entered does not match.',
  'Aucun catalogue sélectionné.': 'No catalog selected.',
  'Ce fichier est hors du dossier collection ou n’est pas un fichier ordinaire.':
    'This file is outside the collection folder or is not a regular file.',
  'Ce fichier dépasse 2 Mo. Ouvrez l’original pour le consulter.':
    'This file exceeds 2 MB. Open the original to read it.',
  'Réponse non HTTP': 'Non-HTTP response',
  Annulé: 'Cancelled',
  'Recherchez les mises à jour ou reconstruisez cette copie.':
    'Check for updates or rebuild this copy.',
  'Recherche des mises à jour…': 'Checking for updates…',
  'Vous utilisez la version à jour.': 'You are using the latest version.',
  'Une mise à jour est disponible.': 'An update is available.',
  'La copie locale est plus récente que l’app.': 'This local copy is newer than the app.',
  'Mise à jour installée. Relancez l’application.': 'Update installed. Relaunch the app.',
  'Application des commits…': 'Applying changes…',
  'Compilation (quelques minutes)…': 'Building (a few minutes)…',
  'Aucune opération en échec à relancer.': 'No failed operations to retry.',
  'Le dépôt a changé depuis la vérification. Recherchez les mises à jour à nouveau.':
    'The repository changed since the last check. Check for updates again.',
  'Node.js est nécessaire pour reconstruire cette app depuis ses sources.':
    'Node.js is required to rebuild this app from source.',
  'Fait corrigé.': 'Fact updated.',
  'Fait invalidé.': 'Fact invalidated.',
  'Fait rétabli.': 'Fact restored.',
  'Banque supprimée.': 'Memory bank deleted.',
  'Modèle mental supprimé.': 'Summary deleted.',
  'Import terminé.': 'Import complete.',
  'Modèle appliqué.': 'Template applied.',
  'Serveur arrêté.': 'Server stopped.',
  'Aucun appel LLM prévu.': 'No LLM calls expected.',
  'Cette action consomme des jetons ; estimation indisponible.':
    'This action uses tokens; no estimate is available.',
};

type Rule = [RegExp, (...groups: string[]) => string];
const rules: Rule[] = [
  [
    /^Hindsight Cloud : connectez votre compte ou configurez (.*)\. Pour un modèle local, choisissez « Sur ce Mac »\.$/,
    (key) =>
      `Hindsight Cloud: connect your account or configure ${key}. For a local model, choose “On this Mac”.`,
  ],
  [/^Démarrage impossible : ([\s\S]*)$/, (detail) => `Startup failed: ${detail}`],
  [/^Redémarrage impossible : ([\s\S]*)$/, (detail) => `Restart failed: ${detail}`],
  [/^Créer la banque « (.*) » \?$/, (id) => `Create memory bank “${id}”?`],
  [/^Renommer « (.*) » en « (.*) » \?$/, (id, name) => `Rename “${id}” to “${name}”?`],
  [/^Afficher « (.*) » sous le nom « (.*) » \?$/, (id, name) => `Display “${id}” as “${name}”?`],
  [/^Retirer l'alias « (.*) » \?$/, (id) => `Remove alias “${id}”?`],
  [
    /^Changer l'identifiant « (.*) » en « (.*) » \?$/,
    (id, next) => `Change identifier “${id}” to “${next}”?`,
  ],
  [
    /^Fusionner « (.*) » dans « (.*) » \?$/,
    (source, target) => `Merge “${source}” into “${target}”?`,
  ],
  [
    /^Supprimer définitivement la banque « (.*) » \?$/,
    (id) => `Permanently delete memory bank “${id}”?`,
  ],
  [/^Supprimer TOUS les faits de « (.*) » \?$/, (id) => `Delete ALL facts from “${id}”?`],
  [
    /^Supprimer tous les faits « (.*) » de « (.*) » \?$/,
    (type, id) => `Delete all “${type}” facts from “${id}”?`,
  ],
  [
    /^Effacer toutes les observations de « (.*) » \?$/,
    (id) => `Clear all observations from “${id}”?`,
  ],
  [/^Modifier « (.*) » pour cette banque \?$/, (key) => `Change “${key}” for this memory bank?`],
  [
    /^Supprimer les (\d+) override\(s\) de la banque \?$/,
    (n) => `Remove the memory bank's ${n} setting overrides?`,
  ],
  [/^Créer la directive « (.*) » \?$/, (name) => `Create directive “${name}”?`],
  [/^Modifier la directive « (.*) » \?$/, (name) => `Edit directive “${name}”?`],
  [/^Supprimer la directive « (.*) » \?$/, (name) => `Delete directive “${name}”?`],
  [/^Créer le modèle mental « (.*) » \?$/, (name) => `Create summary “${name}”?`],
  [/^Rafraîchir « (.*) » \?$/, (name) => `Refresh “${name}”?`],
  [/^Supprimer le modèle mental « (.*) » \?$/, (name) => `Delete summary “${name}”?`],
  [/^Cloner « (.*) » vers « (.*) » \?$/, (source, target) => `Clone “${source}” into “${target}”?`],
  [/^Fusionner l'archive dans « (.*) » \?$/, (id) => `Merge the archive into “${id}”?`],
  [/^Appliquer le modèle à « (.*) » \?$/, (id) => `Apply the template to “${id}”?`],
  [/^Envoyer à « (.*) » \?$/, (id) => `Send to “${id}”?`],
  [
    /^Retirer (\d+) document\(s\) de « (.*) » \?$/,
    (n, id) => `Remove ${n} document(s) from “${id}”?`,
  ],
  [/^Ajouter (\d+) document\(s\) \?$/, (n) => `Add ${n} document(s)?`],
  [/^Passer la portée en « (.*) » \?$/, (scope) => `Change scope to “${scope}”?`],
  [/^Relancer (\d+) opération\(s\) échouée\(s\) \?$/, (n) => `Retry ${n} failed operation(s)?`],
  [/^Annuler ([\d\s]+) opérations? en attente \?$/, (n) => `Cancel ${n} pending operation(s)?`],
  [
    /^Annuler ([\d\s]+) rafraîchissements? en double \?$/,
    (n) => `Cancel ${n} duplicate refresh(es)?`,
  ],
  [/^Activer le journal d'audit pour « (.*) » \?$/, (id) => `Enable the audit log for “${id}”?`],
  [
    /^Désactiver le journal d'audit pour « (.*) » \?$/,
    (id) => `Disable the audit log for “${id}”?`,
  ],
  [/^Connecter (.*) \?$/, (name) => `Connect ${name}?`],
  [/^Se déconnecter de (.*) \?$/, (name) => `Disconnect from ${name}?`],
  [/^Restaurer (.*) \?$/, (name) => `Restore ${name}?`],
  [/^Serveur injoignable : ([\s\S]*)$/, (detail) => `Server unreachable: ${detail}`],
  [/^URL invalide : ([\s\S]*)$/, (detail) => `Invalid URL: ${detail}`],
  [/^HTTP (\d+) sur ([\s\S]*)$/, (status, detail) => `HTTP ${status} at ${detail}`],
  [/^Réponse inattendue pour ([\s\S]*)$/, (detail) => `Unexpected response for ${detail}`],
  [/^Échec : ([\s\S]*)$/, (detail) => `Failed: ${nativeSystemMessage(detail)}`],
  [/^Action inconnue : (.*)$/, (action) => `Unknown action: ${action}`],
  [/^Application construite : (.*)$/, (path) => `Application built: ${path}`],
  [/^Banque « (.*) » créée\.$/, (id) => `Memory bank “${id}” created.`],
];

export function nativeSystemMessage(message: string): string {
  if (getLanguage() !== 'en') return message;
  if (Object.hasOwn(exact, message)) return exact[message];
  for (const [pattern, render] of rules) {
    const match = pattern.exec(message);
    if (match) return render(...match.slice(1));
  }
  return message;
}

const bodies: Record<string, string> = {
  'Banque vide, réglages par défaut du serveur.':
    'Empty memory bank with the server’s default settings.',
  'Banque vide, réglages par défaut du serveur, avec la mission indiquée.':
    'Empty memory bank with the server’s default settings and the mission you entered.',
  "Seul le nom affiché change : l'identifiant, les données et les clients (MCP, scripts) ne sont pas touchés.":
    'Only the display name changes. The identifier, data and clients (MCP, scripts) are unchanged.',
  'Son contenu et son historique sont supprimés.': 'Its content and history will be deleted.',
  "Le nouveau texte sera ré-indexé ; les observations et liens qui en dérivent sont supprimés puis reconsolidés (appel LLM de consolidation).\n\nL'ancienne version reste dans l'archive de curation du serveur.":
    'The new text will be reindexed. Derived observations and links will be deleted and consolidated again (consolidation LLM call).\n\nThe previous version remains in the server’s curation archive.',
  "Le serveur exige le texte avec toute correction : il sera ré-indexé tel quel, et les observations qui en dérivent reconsolidées.\n\nL'ancienne version reste dans l'archive de curation du serveur.":
    'The server requires text with every edit: it will be reindexed as-is and its derived observations will be consolidated again.\n\nThe previous version remains in the server’s curation archive.',
  'Les faits sont conservés ; les observations seront recréées par une nouvelle consolidation (appels LLM).':
    'Facts are kept. Observations will be recreated through a new consolidation (LLM calls).',
  "Irréversible. Les documents restent, mais leurs faits disparaissent. Exportez la banque d'abord.":
    'Irreversible. Documents remain, but their facts are deleted. Export the memory bank first.',
  "Faits, documents, entités, observations, configuration : tout est supprimé, sans retour possible. Exportez-la d'abord.":
    'Facts, documents, entities, observations and settings will all be permanently deleted. Export the memory bank first.',
  'La banque revient aux valeurs globales du serveur (missions, disposition, réglages de rétention/recall…).':
    'The memory bank returns to the server’s global settings (missions, disposition, retention and recall settings…).',
  "Il sera exclu du recall et de la consolidation ; ses liens et observations dérivées sont retirés. C'est réversible (« Rétablir »).":
    'It will be excluded from recall and consolidation. Its derived links and observations will be removed. You can reverse this with Restore.',
  'Il redevient visible du recall et sera reconsolidé.':
    'It will be included in recall again and reconsolidated.',
  'Les observations qui en dérivent sont supprimées ; elles pourront être recréées par la prochaine consolidation.':
    'Derived observations will be deleted. The next consolidation can recreate them.',
  'Toutes les banques sont concernées.': 'All memory banks are affected.',
  'Les estimations de coût utiliseront cette grille dans Hindsight Desktop.':
    'Hindsight Desktop will use this price list for cost estimates.',
  'Un court appel sera effectué pour chaque rôle LLM configuré. Cette vérification consomme des jetons.':
    'A short call will be made for each configured LLM role. This check uses tokens.',
  "Ce relevé ponctuel lit la session Codex dans ~/.codex/auth.json et, si vous l'autorisez, la session Claude Code dans le Trousseau. Les jetons servent uniquement à interroger chatgpt.com et api.anthropic.com ; ils ne sont ni enregistrés par l'app, ni envoyés au serveur Hindsight. Aucun appel à un modèle. Aucun relevé automatique n'est activé.":
    'This one-time check reads the Codex session in ~/.codex/auth.json and, if you allow it, the Claude Code session in Keychain. Tokens are used only to query chatgpt.com and api.anthropic.com. The app does not save them or send them to the Hindsight server. No model is called. Automatic checks remain off.',
  "hindsight-admin ouvrira Hindsight Cloud dans le navigateur : connectez-vous (ou créez un compte), choisissez une organisation et approuvez. La clé créée est enregistrée dans ~/.hindsight/cloud/credentials.json, lisible par vous seul, et ses appels sont facturés sur les crédits de l'organisation.":
    'hindsight-admin will open Hindsight Cloud in your browser. Sign in or create an account, choose an organization and approve. The new key is stored in ~/.hindsight/cloud/credentials.json and is readable only by you. Calls are billed against your organization’s credits.',
  'Le client officiel ouvrira une connexion à votre compte. La session reste dans le stockage de ce client sur ce Mac.':
    'The official client will open a sign-in flow. Your session stays in that client’s storage on this Mac.',
  "Les requêtes en cours seront interrompues ; les opérations en file reprendront au prochain démarrage. L'app restera ouverte mais déconnectée.":
    'Current requests will be interrupted. Queued operations will resume at the next start. The app will stay open but disconnected.',
  'Les requêtes en cours seront interrompues ; les opérations en file reprendront au redémarrage.':
    'Current requests will be interrupted. Queued operations will resume after the restart.',
  "Le script actuel sera remplacé par cette sauvegarde (il est lui-même sauvegardé d'abord). Redémarrez ensuite le serveur.":
    'This backup will replace the current script, after backing it up. Restart the server afterwards.',
  'Hindsight repassera par ses appels LLM tant que le modèle est arrêté. Le service redémarrera à la prochaine ouverture de session.':
    'Hindsight will use LLM calls while this model is stopped. The service will restart at the next login.',
  'Le serveur va redémarrer avec son worker : les opérations en attente seront traitées (consommation LLM).':
    'The server will restart with its worker. Pending operations will be processed (LLM usage).',
  "Le serveur est arrêté : il traitera sa file à son prochain démarrage. Il n'est pas démarré pour autant.":
    'The server is stopped. Its queue will be processed the next time it starts. This action does not start it.',
  'Les prochains accès ne seront plus enregistrés. Les entrées existantes sont conservées.':
    'Future accesses will no longer be recorded. Existing entries are kept.',
  'Le serveur enregistrera chaque accès à cette banque (action, transport, requête, réponse). Les accès passés ne sont pas récupérables. Écrit `audit_log_enabled = true` dans la configuration de la banque (PATCH …/config).':
    'The server will record every access to this memory bank (action, transport, request, response). Past accesses cannot be recovered. Sets `audit_log_enabled = true` in the memory bank configuration (PATCH …/config).',
  "Tous les échecs de la banque ont été recherchés, indépendamment des filtres de l'écran. Les sous-opérations seront remises en file ; les lots parents suivront leur progression. Cela peut consommer des appels LLM. Vérifiez d'abord les réglages des modèles : la relance ne corrige pas un quota épuisé ou une erreur de connexion.":
    'All failures in this memory bank were checked, regardless of the screen filters. Sub-operations will be requeued and parent batches will track their progress. This may use LLM calls. Check model settings first: retrying does not fix an exhausted quota or a connection error.',
};

function costSummary(message: string): string {
  if (message === 'Aucun appel LLM prévu.') return exact[message];
  if (!/^Estimation : ≈ [^\n]+ jetons LLM/.test(message)) return nativeSystemMessage(message);
  return message
    .replace(/^Estimation : /, 'Estimate: ')
    .replace(' jetons LLM', ' LLM tokens')
    .replace(' facturés', ' billed')
    .replace("pris sur l'abonnement", 'uses subscription quota')
    .replace(" à l'usage)", ' pay-as-you-go equivalent)')
    .replace('tarif inconnu pour une partie', 'some pricing is unknown')
    .replace(
      /calibrée sur (\d+) appels LLM récents de cette banque/,
      'calibrated on $1 recent LLM calls from this memory bank',
    )
    .replace('valeurs par défaut (aucune trace récente)', 'default values (no recent traces)')
    .replace("mesurée sur l'essai à blanc", 'measured from the preview');
}

const messageRules: Array<[RegExp, Rule]> = [
  [
    /^Retirer l'alias « .* » \?$/,
    [
      /^Les clients qui utilisent encore « (.*) » n'atteindront plus cette banque \(et risquent d'en créer une vide\)\. Les données ne bougent pas\.$/,
      (alias) =>
        `Clients still using “${alias}” will no longer reach this memory bank and could create an empty one. Data is unchanged.`,
    ],
  ],
  [
    /^Retirer \d+ document\(s\) de « .* » \?$/,
    [
      /^([\s\S]*) : ([\d\s]+) documents? et ([\d\s]+) faits? supprimés définitivement de la banque\. Les fichiers ne sont pas touchés ; les renvoyer coûtera une nouvelle extraction\.$/,
      (what, docs, facts) =>
        `${what}: ${docs} document(s) and ${facts} fact(s) will be permanently deleted from the memory bank. Files are kept. Sending them again will require a new extraction and its cost.`,
    ],
  ],
  [
    /^Modifier les tags du document \?$/,
    [
      /^Ajoutés : ([\s\S]*)\nRetirés : ([\s\S]*)\n\nLes tags sont propagés à tous ses faits ; les observations concernées sont invalidées et reconsolidées sous les nouveaux tags \(appel LLM\)\.$/,
      (added, removed) =>
        `Added: ${added}\nRemoved: ${removed}\n\nTags are applied to all document facts. Affected observations are invalidated and consolidated again under the new tags (LLM call).`,
    ],
  ],
  [
    /^Passer la portée en « .* » \?$/,
    [
      /^Actuelle : ([\s\S]*)\. Les faits ne sont pas réextraits\. Ceux dont le compartiment d'observations change perdent leurs observations et repartent en consolidation \(appel LLM\), avec les faits d'autres documents qui les partageaient\. Un changement sans effet sur les compartiments ne relance rien\.$/,
      (current) =>
        `Current: ${current}. Facts are not extracted again. Facts whose observation scope changes lose their observations and are consolidated again (LLM call), along with facts from other documents that shared those observations. If scopes are unaffected, nothing is rerun.`,
    ],
  ],
  [
    /^Annuler [\d\s]+ opérations? en attente \?$/,
    [
      /^([\d\s]+) opérations? en attente dans ([\d\s]+) banques? (?:sera annulée|seront annulées) : (?:son|leur) contenu ne sera pas extrait\.\nC'est définitif : pour l'ajouter plus tard, il faudra le renvoyer \(depuis Documents ou Importer\)\.\nUne opération déjà commencée quand vous confirmez est interrompue à sa prochaine étape ; les faits déjà extraits ne sont pas touchés\.$/,
      (n, banks) =>
        `${n} pending operation(s) in ${banks} memory bank(s) will be cancelled. Their content will not be extracted.\nThis is final: to add it later, send it again from Documents or Import.\nAn operation that has already started when you confirm will be interrupted at its next stage. Previously extracted facts are kept.`,
    ],
  ],
  [
    /^Désinstaller le service Hindsight \?$/,
    [
      /^Le serveur sera arrêté s'il tourne, et l'agent (.*) supprimé\. Le script de lancement, les données du serveur et le journal sont conservés\.$/,
      (agent) =>
        `The server will be stopped if running and agent ${agent} will be removed. The launch script, server data and log are kept.`,
    ],
  ],
  [
    /^Désinstaller le modèle de décision local \?$/,
    [
      /^Supprime le service et ([\s\S]*) \(environnement Python, modèle et clé, environ 2 Go\)\. Choisissez d'abord un autre modèle de décision dans le script du serveur\.$/,
      (path) =>
        `Deletes the service and ${path} (Python environment, model and key, approximately 2 GB). Select another decision model in the server script first.`,
    ],
  ],
  [
    /^Se déconnecter de .* \?$/,
    [
      /^La clé enregistrée sur ce Mac \(~\/\.hindsight\/cloud\/credentials.json\) sera effacée : les modèles Hindsight Cloud du serveur n'auront plus de clé\. Elle reste valide jusqu'à sa révocation sur (.*)\.$/,
      (url) =>
        `The key stored on this Mac (~/.hindsight/cloud/credentials.json) will be erased. The server's Hindsight Cloud models will no longer have a key. The key remains valid until you revoke it at ${url}.`,
    ],
  ],
  [
    /^Supprimer définitivement ce document \?$/,
    [
      /^Le document, ses chunks et ses (\d+) fait\(s\) sont supprimés\. Irréversible : exportez d'abord si besoin\.$/,
      (n) =>
        `The document, its chunks and its ${n} fact(s) will be deleted. This is irreversible: export first if needed.`,
    ],
  ],
  [
    /^Retraiter ce document \?$/,
    [
      /^Ses (\d+) fait\(s\) seront supprimés puis ré-extraits avec la configuration actuelle du serveur \(appels LLM et VLM\)\. Les corrections manuelles faites sur ces faits seront perdues\.(?:\n\n([^\n]+))?$/,
      (n, cost) =>
        `Its ${n} fact(s) will be deleted and extracted again using the current server configuration (LLM and VLM calls). Manual corrections to these facts will be lost.${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Mettre les traitements en pause \?$|^Reprendre les traitements \?$/,
    [/^Banque : (.*)\.$/, (id) => `Memory bank: ${id}.`],
  ],
  [
    /^Interroger la mémoire \?$/,
    [
      /^Le modèle rédigera une réponse à partir des faits de cette banque\.\n\n([^\n]+)\n\n([\s\S]*)$/,
      (cost, query) =>
        `The model will write an answer from the facts in this memory bank.\n\n${costSummary(cost)}\n\n${query}`,
    ],
  ],
  [
    /^Rafraîchir « .* » \?$/,
    [
      /^Le modèle mental est régénéré par le LLM \(opération asynchrone\)\.(?:\n\n([^\n]+))?$/,
      (cost) =>
        `The summary will be regenerated by the LLM (asynchronous operation).${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Créer le modèle mental « .* » \?$/,
    [
      /^Question source : ([\s\S]*)\n\nSon contenu est généré par le LLM \(opération asynchrone\)\.(?:\n\n([^\n]+))?$/,
      (query, cost) =>
        `Source question: ${query}\n\nIts content is generated by the LLM (asynchronous operation).${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Retirer de la mémoire \?$/,
    [
      /^([\s\S]*)\n\nLe fichier local est conservé\. Cette source sera exclue des prochains envois\. Le document et ses faits seront retirés de Hindsight après sauvegarde locale du texte et des métadonnées\.$/,
      (target) =>
        `${target}\n\nThe local file is kept. This source will be excluded from future uploads. Its document and facts will be removed from Hindsight after backing up the text and metadata locally.`,
    ],
  ],
  [
    /^Envoyer les sources à Hindsight \?$/,
    [
      /^(\d+) sources complètes vers « (.*) », environ (\d+) jetons de texte avant extraction\.\n\n([\s\S]*)\n\nLes sources modifiées remplacent leur version mémorisée\. Aucune suppression d’autres documents\. La consolidation dépend des réglages de la banque\.$/,
      (n, bank, tokens, items) =>
        `${n} complete sources to “${bank}”, approximately ${tokens} text tokens before extraction.\n\n${items}\n\nChanged sources replace their stored version. Other documents are kept. Consolidation follows the memory bank settings.`,
    ],
  ],
  [
    /^Lancer la consolidation \?$/,
    [
      /^Le serveur va créer\/mettre à jour les observations à partir des faits non consolidés \((\d+) en attente\)\. Cela appelle le LLM de consolidation\. Chaque fait se fond dans les observations de sa portée \(celle de son document\)\.(?:\n\n([^\n]+))?$/,
      (n, cost) =>
        `The server will create or update observations from unconsolidated facts (${n} pending). This calls the consolidation LLM. Each fact contributes to observations in its scope (its document's scope).${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Réessayer les faits en échec de consolidation \?$/,
    [
      /^(\d+) fait\(s\) marqués « échec définitif » seront remis dans la file de consolidation \(aucune observation supprimée\)\.$/,
      (n) =>
        `${n} fact(s) marked as permanently failed will be requeued for consolidation. No observations are deleted.`,
    ],
  ],
  [
    /^Annuler cette opération \?$/,
    [
      /^« ([\s\S]*) » sera interrompue si elle est en attente ou en cours\.$/,
      (title) => `“${title}” will be interrupted if it is pending or running.`,
    ],
  ],
  [
    /^Supprimer cette entrée \?$/,
    [
      /^L'entrée d'historique « ([\s\S]*) » sera supprimée du serveur\. Les faits déjà créés ne sont pas touchés\.$/,
      (title) =>
        `History entry “${title}” will be deleted from the server. Existing facts are kept.`,
    ],
  ],
  [
    /^Relancer cette opération \?$/,
    [
      /^« ([\s\S]*) »([\s\S]*) sera remise en file\. Selon son type, cela peut consommer des appels LLM\.$/,
      (title, target) =>
        `“${title}”${target} will be requeued. Depending on its type, this may use LLM calls.`,
    ],
  ],
  [
    /^Revenir à la configuration du serveur \?$/,
    [
      /^Les (\d+) réglage\(s\) propres à « (.*) » sont supprimés, y compris ceux de l'administration \(journal d'audit, etc\.\)\. Les faits existants ne changent pas\.$/,
      (n, bank) =>
        `The ${n} setting override(s) for “${bank}” will be removed, including administration settings (audit log, etc.). Existing facts are unchanged.`,
    ],
  ],
  [
    /^Collecter les sources \?$/,
    [
      /^Le collecteur de ce dossier sera exécuté avec vos droits\. Il relit les conversations, GitHub, W&B et les rapports selon la configuration du projet, puis actualise les archives locales\. Aucun envoi ni traitement Hindsight\.\n\nDossier : ([\s\S]*)$/,
      (path) =>
        `This folder's collector will run with your permissions. It reads conversations, GitHub, W&B and reports according to the project configuration, then updates local archives. Nothing is uploaded or processed by Hindsight.\n\nFolder: ${path}`,
    ],
  ],
];

function confirmationMessage(confirmation: Confirmation): string {
  const { title, message } = confirmation;
  // Les directives contiennent directement le texte de l’utilisateur, même lorsqu’il
  // ressemble à une phrase système connue : leur corps ne passe jamais au dictionnaire.
  if (/^(Créer|Modifier|Supprimer) la directive « /.test(title) || /^Modifier « /.test(title))
    return message;
  if (Object.hasOwn(bodies, message)) return bodies[message];
  for (const [titlePattern, [pattern, render]] of messageRules) {
    if (!titlePattern.test(title)) continue;
    const match = pattern.exec(message);
    if (match) return render(...match.slice(1));
  }
  return advancedConfirmationMessage(title, message);
}

export function localizeConfirmation(confirmation: Confirmation): Confirmation {
  if (getLanguage() !== 'en') return confirmation;
  return {
    ...confirmation,
    title: nativeSystemMessage(confirmation.title),
    message: confirmationMessage(confirmation),
    confirmTitle: nativeSystemMessage(confirmation.confirmTitle),
  };
}

export function localizeNativeSnapshot(snapshot: Snapshot): Snapshot {
  if (getLanguage() !== 'en') return snapshot;
  const data: Row = { ...snapshot.data };
  if (snapshot.section === 'server' || snapshot.section === 'model-settings') {
    const text = (value: unknown) => (typeof value === 'string' ? nativeCatalogText(value) : value);
    const fields = (items: Row[]) =>
      items.map((field) => ({
        ...field,
        label: text(field.label),
        help: text(field.help),
      }));
    if (Array.isArray(data.providerChoices))
      data.providerChoices = data.providerChoices.map((choice: Row) => ({
        ...choice,
        title: choice.title === choice.id ? choice.title : text(choice.title),
      }));
    if (Array.isArray(data.roles))
      data.roles = data.roles.map((role: Row) => ({
        ...role,
        title: text(role.title),
        effective: nativeRoleEffective(role, snapshot.data.roles),
        fields: Array.isArray(role.fields) ? fields(role.fields) : role.fields,
      }));
    if (Array.isArray(data.otherVariables)) data.otherVariables = fields(data.otherVariables);
    if (Array.isArray(data.accounts))
      data.accounts = data.accounts.map((account: Row) => ({
        ...account,
        status: text(account.status),
      }));
    if (Array.isArray(data.warnings)) data.warnings = data.warnings.map(text);
    if (data.service)
      data.service = {
        ...data.service,
        scriptWarning: text(data.service.scriptWarning),
        error: text(data.service.error),
        message: text(data.service.message),
      };
    if (Array.isArray(data.configurationProblems))
      data.configurationProblems = data.configurationProblems.map(text);
    if (data.hindsightModels?.local)
      data.hindsightModels = {
        ...data.hindsightModels,
        local: {
          ...data.hindsightModels.local,
          problem: text(data.hindsightModels.local.problem),
          summary: text(data.hindsightModels.local.summary),
        },
      };
  }

  for (const key of ['error', 'memoryMessage', 'actionMessage', 'activityMessage'])
    if (typeof data[key] === 'string') data[key] = nativeSystemMessage(data[key]);
  return {
    ...snapshot,
    app: {
      ...snapshot.app,
      connectionError: snapshot.app.connectionError
        ? nativeSystemMessage(snapshot.app.connectionError)
        : snapshot.app.connectionError,
    },
    updates: snapshot.updates
      ? {
          ...snapshot.updates,
          message:
            typeof snapshot.updates.message === 'string'
              ? nativeSystemMessage(snapshot.updates.message)
              : snapshot.updates.message,
        }
      : undefined,
    data,
    confirmations: snapshot.confirmations.map(localizeConfirmation),
    messages: snapshot.messages.map(nativeSystemMessage),
  };
}
