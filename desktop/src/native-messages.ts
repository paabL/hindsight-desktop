import { getLanguage } from './i18n-core.ts';
import { advancedConfirmationMessage, operationTitle } from './native-confirmations.ts';
import { nativeCatalogText, nativeRoleEffective } from './native-catalog.ts';
import type { Confirmation, Row, Snapshot } from './types';

// Seuls les champs système du pont sont localisés. Le contenu des documents, les noms,
// les requêtes, les identifiants et le texte à retaper restent intacts.
const exact: Record<string, string> = {
  "Le moteur Hindsight s'est interrompu. Vérifiez « Activité › Traitements » avant de réessayer, puis reconnectez le serveur.":
    'The Hindsight engine stopped. Check Activity › Processing before trying again, then reconnect the server.',
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
  'Fournisseur de modèle inconnu.': 'Unknown model provider.',
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
  'Effacer les faits': 'Clear facts',
  'Aucune observation à effacer.': 'No observations to clear.',
  'Opération annulée.': 'Operation cancelled.',
  'Entrée supprimée.': 'Entry deleted.',
  'Opération relancée.': 'Operation retried.',
  "Ce serveur n'accepte pas les réglages par banque. Pour les activer, ajoutez HINDSIGHT_API_ENABLE_BANK_CONFIG_API=true au script de lancement, puis redémarrez le serveur.":
    'This server does not accept per-bank settings. To enable them, add HINDSIGHT_API_ENABLE_BANK_CONFIG_API=true to the launch script, then restart the server.',
  "Ce serveur n'accepte pas les réglages par banque : activez le journal côté serveur en ajoutant `HINDSIGHT_API_AUDIT_LOG_ENABLED=true` au script de lancement, puis redémarrez-le.":
    'This server does not accept per-bank settings: turn the log on server-side by adding `HINDSIGHT_API_AUDIT_LOG_ENABLED=true` to the launch script, then restart it.',
  "État du journal d'accès inconnu : actualisez la page avant de le modifier.":
    'Access log state unknown: refresh the page before changing it.',
  'Aucun fait à effacer.': 'No facts to clear.',
  Rétablir: 'Restore',
  Invalider: 'Invalidate',
  Retraiter: 'Reprocess',
  Régénérer: 'Regenerate',
  'Enregistrer et régénérer': 'Save and regenerate',
  Cloner: 'Clone',
  Fusionner: 'Merge',
  'Appliquer le gabarit': 'Apply template',
  'Exécuter maintenant': 'Run now',
  'Enregistrer les étiquettes': 'Save tags',
  'Mettre toutes les banques en pause': 'Pause all memory banks',
  'Gabarit appliqué.': 'Template applied.',
  'Documents sélectionnés :': 'Selected documents:',
  '1 document existant sera REMPLACÉ : ses faits sont supprimés puis réextraits.':
    '1 existing document will be REPLACED: its facts are deleted and extracted again.',
  "Les images intégrées aux HTML sont retirées. L'extraction se fait en tâche de fond ; suivez-la dans « Activité › Traitements ».":
    'Images embedded in HTML are removed. Extraction runs in the background. Follow it in Activity › Processing.',
  "Ils s'appliquent aux PROCHAINES extractions, consolidations et réponses : les faits déjà extraits ne changent pas (retraitez un document pour lui appliquer la nouvelle extraction).":
    'They apply to FUTURE extractions, consolidations and answers. Facts already extracted do not change (reprocess a document to apply the new extraction to it).',
  "Conseil : testez d'abord l'extraction avec l'essai à blanc.":
    'Tip: try the extraction with a dry run first.',
  "Sans observations, plus de consolidation : la recherche et les réponses ne s'appuient plus que sur les faits.":
    'Without observations there is no consolidation: search and answers rely on facts only.',
  'Sans texte des documents, le lecteur ne pourra plus afficher les nouveaux documents, et le retraitement sera impossible pour eux.':
    'Without document text, the reader cannot show new documents, and they cannot be reprocessed.',
  "Une copie de l'état actuel sera faite à côté du fichier avant l'écriture. Rien ne change pour le serveur tant qu'il n'est pas redémarré.":
    'A copy of the current file is saved next to it before writing. Nothing changes for the server until it restarts.',
  'Le fichier change (voir le diff).': 'The file changes (see the diff).',
  "Le style d'extraction « Personnalisé » demande des instructions d'extraction.":
    'The “Custom” extraction style needs extraction instructions.',
  'Taille des segments trop petite (au moins 100 caractères).':
    'Chunk size too small (at least 100 characters).',
  Restaurer: 'Restore',
  Envoyer: 'Upload',
  Importer: 'Import',
  Ajouter: 'Add',
  Collecter: 'Collect',
  Renommer: 'Rename',
  "Changer l'identifiant": 'Change identifier',
  'Changer la portée': 'Change scope',
  Lancer: 'Start',
  Relancer: 'Retry',
  'Tout relancer': 'Retry all',
  "Annuler l'opération": 'Cancel operation',
  'Remettre en file': 'Requeue',
  'Mettre en pause': 'Pause',
  Reprendre: 'Resume',
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
  'Obtenir la réponse': 'Get the answer',
  'Tester les modèles': 'Test models',
  'Vérifier / reprendre': 'Check / resume',
  "Lancer l'essai": 'Start the dry run',
  'Obtenir une réponse ?': 'Get an answer?',
  'Envoyer les sources à Hindsight ?': 'Upload sources to Hindsight?',
  'Vérifier ou reprendre l’envoi initial ?': 'Check or resume the original upload?',
  'Retirer de la mémoire ?': 'Remove from memory?',
  'Collecter les sources ?': 'Collect sources?',
  'Enregistrer les étiquettes du document ?': 'Save document tags?',
  'Retraiter ce document ?': 'Reprocess this document?',
  'Supprimer définitivement ce document ?': 'Permanently delete this document?',
  'Corriger ce fait ?': 'Edit this fact?',
  'Invalider ce fait ?': 'Invalidate this fact?',
  'Rétablir ce fait ?': 'Restore this fact?',
  'Effacer les observations issues de ce fait ?': 'Clear observations derived from this fact?',
  "Restaurer l'archive dans une nouvelle banque ?": 'Restore the archive into a new memory bank?',
  'Enregistrer le comportement de la mémoire ?': 'Save memory behavior?',
  'Revenir aux réglages du serveur ?': 'Reset to server settings?',
  'Revenir aux réglages du serveur': 'Reset to server settings',
  "Cette banque n'a aucun réglage propre : elle suit déjà le serveur.":
    'This memory bank has no bank-specific settings: it already follows the server.',
  "Essai à blanc de l'extraction ?": 'Dry-run the extraction?',
  'Relancer cette opération ?': 'Retry this operation?',
  'Exécuter cette opération maintenant ?': 'Run this operation now?',
  'Annuler cette opération ?': 'Cancel this operation?',
  'Supprimer cette entrée ?': 'Delete this history entry?',
  'Consolider les faits ?': 'Consolidate facts?',
  Consolider: 'Consolidate',
  'Reconsolider les faits en échec ?': 'Reconsolidate failed facts?',
  Reconsolider: 'Reconsolidate',
  "La consolidation est désactivée pour cette banque : le serveur ne crée pas d'observations. Activez « Créer des observations » dans « Réglages › Comportement de la mémoire › Consolidation ».":
    'Consolidation is turned off for this memory bank: the server does not create observations. Turn on “Create observations” in Settings › Memory behavior › Consolidation.',
  'Une consolidation est déjà en cours pour cette banque.':
    'A consolidation is already running for this memory bank.',
  'Rien à consolider : tous les faits de cette banque sont déjà consolidés.':
    'Nothing to consolidate: every fact in this memory bank is already consolidated.',
  'Consolidation mise en file.': 'Consolidation queued.',
  "Une consolidation était déjà en file : cette demande l'a rejointe.":
    'A consolidation was already queued: this request joined it.',
  'Aucun fait en échec de consolidation.': 'No facts failed consolidation.',
  'Faits remis en file.': 'Facts requeued.',
  "Ce document ne peut pas être retraité : son texte original n'est pas stocké sur le serveur.":
    'This document cannot be reprocessed: its original text is not stored on the server.',
  'Une consolidation est déjà en attente pour cette banque.':
    'A consolidation is already queued for this memory bank.',
  'Mettre toutes les banques en pause ?': 'Pause all memory banks?',
  'Reprendre toutes les banques ?': 'Resume all memory banks?',
  'Toutes les banques sont déjà en pause.': 'All memory banks are already paused.',
  'Modèle mental créé ; sa génération est en file : suivi dans « Activité › Traitements ».':
    'Mental model created. Its generation is queued: follow it in Activity › Processing.',
  'Retraitement en file : suivez-le dans « Activité › Traitements ».':
    'Reprocessing queued: follow it in Activity › Processing.',
  "L'opération n'est pas encore terminée ; suivez-la dans « Activité › Traitements ».":
    'The operation has not finished yet. Follow it in Activity › Processing.',
  'Consolidation automatique mise en accord avec la pause.':
    'Automatic consolidation now matches the pause.',
  "Aucune banque n'est en pause.": 'No memory bank is paused.',
  'Enregistrer les plafonds ?': 'Save limits?',
  'Modifier la grille tarifaire ?': 'Change the price list?',
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
  'Ce dossier est introuvable.': 'This folder cannot be found.',
  "Choisissez une banque avant d'ajouter un dossier.":
    'Choose a memory bank before adding a folder.',
  'Format de document non autorisé.': 'Document format is not allowed.',
  'Lien non autorisé.': 'Link is not allowed.',
  'Entité inconnue ; rechargez les filtres.': 'Unknown entity; reload the filters.',
  'Pièce jointe inconnue.': 'Unknown attachment.',
  'Période inconnue.': 'Unknown period.',
  'Cette pièce jointe dépasse 12 Mo.': 'This attachment exceeds 12 MB.',
  'Connaissance inconnue.': 'Unknown knowledge item.',
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
  'Aucun nouveau commit : cette copie du code source est à jour.':
    'No new commits: this source copy is up to date.',
  'De nouveaux commits sont disponibles dans le dépôt source.':
    'New commits are available in the source repository.',
  // Plafonds, comportement de la mémoire et test des modèles.
  "Coût estimé aujourd'hui": 'Estimated cost today',
  'Aucun changement à enregistrer.': 'No changes to save.',
  'Choisissez une banque : le test des modèles passe par une banque du serveur.':
    'Choose a memory bank: the model test runs through a server memory bank.',
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
  'Modèle mental supprimé.': 'Mental model deleted.',
  'Modèle mental renommé.': 'Mental model renamed.',
  'Page de connaissance renommée.': 'Knowledge page renamed.',
  'Le nom ne peut pas être vide.': 'The name cannot be empty.',
  'La question ne peut pas être vide.': 'The question cannot be empty.',
  'Aucune modification à enregistrer.': 'No changes to save.',
  "Cette page n'apparaît plus dans la base de connaissance : rien n'a été modifié.":
    'This page no longer appears in the knowledge base. Nothing was changed.',
  'Import terminé.': 'Import complete.',
  'Serveur arrêté.': 'Server stopped.',
  'Aucun appel LLM prévu.': 'No LLM calls expected.',
  'Cette action consomme des jetons ; estimation indisponible.':
    'This action uses tokens; no estimate is available.',

  // Messages d’état du moteur : banques, réglages de la banque, file, service, sources.
  'Identifiant invalide (lettres, chiffres, « - », « _ », « . »).':
    'Invalid ID (letters, digits, “-”, “_”, “.”).',
  'Alias invalide (lettres, chiffres, « - », « _ », « . »).':
    'Invalid alias (letters, digits, “-”, “_”, “.”).',
  'Identifiant invalide.': 'Invalid ID.',
  'Alias retiré.': 'Alias removed.',
  'Une opération sur les banques est déjà en cours.':
    'A memory bank operation is already in progress.',
  'Choisissez deux banques différentes.': 'Choose two different memory banks.',
  'Le clone doit porter un nouvel identifiant.': 'The clone needs a new ID.',
  "L'export est terminé mais le serveur n'indique pas où télécharger l'archive.":
    'The export finished, but the server did not say where to download the archive.',
  'Réglages du serveur rétablis.': 'Server settings restored.',
  'Directive créée.': 'Directive created.',
  'Directive mise à jour.': 'Directive updated.',
  'Directive supprimée.': 'Directive deleted.',
  'Page de connaissance supprimée.': 'Knowledge page deleted.',
  'Le service est déjà en cours de modification.': 'The service is already being changed.',
  'Ce document n’est plus ouvert.': 'This document is no longer open.',
  'Le serveur est en mode consultation : le test des modèles est désactivé.':
    'The server is in read-only mode: the model test is turned off.',
  'Choisissez une banque pour tester les modèles : le test passe par une banque du serveur.':
    'Choose a memory bank to test models: the test runs through a server memory bank.',
  "Le serveur n'a renvoyé aucun résultat pour le test des modèles.":
    'The server returned no result for the model test.',
  'Le test des modèles n’a pas abouti.': 'The model test did not complete.',
  "Le test des modèles n'a pas abouti.": 'The model test did not complete.',
  'Le rôle LLM testé répond.': 'The tested LLM role responds.',
  "Filtre d'opérations inconnu.": 'Unknown operations filter.',
  'Le test des LLM est désactivé sur ce serveur. La relance des opérations reste disponible. Pour activer ce diagnostic, ajoutez HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true au script de lancement, puis redémarrez le serveur.':
    'LLM testing is disabled on this server. Retrying operations is still available. To enable this check, add HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true to the launch script, then restart the server.',
  "Pause en cours sur toutes les banques : rien n'est envoyé. Reprenez depuis « Activité › Traitements ».":
    'All memory banks are paused: nothing is sent. Resume from Activity › Processing.',
  'Toutes les banques sont en pause.': 'All memory banks are paused.',
  'Aucune opération en attente.': 'No pending operations.',
  "Le modèle installé sur ce Mac nécessite un serveur Hindsight local. Sélectionnez d'abord son adresse locale.":
    'The model installed on this Mac requires a local Hindsight server. Select its local address first.',
  'Les réglages ont changé depuis la confirmation. Rechargez le script et réessayez.':
    'Settings changed since the confirmation. Reload the script and try again.',
  'Sauvegarde restaurée. Redémarrez le serveur pour appliquer.':
    'Backup restored. Restart the server to apply it.',
  'Le script a changé depuis la confirmation : vérifiez-le à nouveau.':
    'The script changed since the confirmation. Review it again.',
  'Installez le service Hindsight (ci-dessus) ou indiquez la commande qui redémarre votre serveur.':
    'Install the Hindsight service (above) or enter the command that restarts your server.',
  'Le serveur, la banque ou le script a changé depuis la confirmation. Réessayez.':
    'The server, memory bank or script changed since the confirmation. Try again.',
  'Le contexte a changé pendant le redémarrage. Actualisez le serveur et la banque sélectionnés.':
    'The context changed during the restart. Refresh the selected server and memory bank.',
  'Le contexte a changé pendant le test des LLM. Actualisez le diagnostic.':
    'The context changed during the LLM test. Refresh the check.',
  'Serveur redémarré, mais le diagnostic LLM ne contient aucun résultat.':
    'Server restarted, but the LLM check returned no results.',
  'La copie locale contient des modifications. Enregistrez-les dans Git avant d’appliquer les commits distants, ou utilisez Recompiler cette copie.':
    'This local copy has changes. Commit them in Git before applying remote commits, or use Rebuild this copy.',
  'Le service de ce Mac doit être vérifié avec une adresse locale. Sélectionnez le serveur local avant de le démarrer ou de modifier sa file.':
    'This Mac’s service must be checked with a local address. Select the local server before starting it or changing its queue.',
  'Service désinstallé.': 'Service uninstalled.',
  "Installez d'abord le service Hindsight.": 'Install the Hindsight service first.',
  'Un serveur répond déjà à cette adresse : arrêtez-le avant de démarrer le service.':
    'A server is already responding at this address. Stop it before starting the service.',
  'Vérifiez et approuvez le script du service avant de redémarrer.':
    'Review and approve the service script before restarting.',
  "Le script ou l'adresse du serveur a changé pendant l'opération. Vérifiez les réglages et réessayez.":
    'The script or the server address changed during the operation. Check the settings and try again.',
  "Le script a changé pendant l'installation : vérifiez-le à nouveau.":
    'The script changed during installation. Review it again.',
  'Vérifiez et approuvez le script du service avant de démarrer.':
    'Review and approve the service script before starting.',
  "Le service est arrêté, mais l'API répond encore : un autre serveur tourne à cette adresse (lancé hors de l'app).":
    'The service is stopped, but the API still responds: another server is running at this address (started outside the app).',
  'Le service utilise un autre script. Réinstallez-le avec le script sélectionné avant de modifier sa file.':
    'The service uses another script. Reinstall it with the selected script before changing its queue.',
  "L'ancienne API répond encore après l'arrêt du service.":
    'The old API still responds after the service stopped.',
  "Le script ou l'adresse du serveur a changé pendant le démarrage. Actualisez son état.":
    'The script or the server address changed during startup. Refresh its status.',
  // Modèle de décision local : états et étapes d'installation.
  'État inconnu': 'Unknown state',
  'Non installé': 'Not installed',
  'Installé, arrêté': 'Installed, stopped',
  'Démarrage…': 'Starting…',
  'En marche sur ce Mac': 'Running on this Mac',
  "Création de l'environnement Python…": 'Creating the Python environment…',
  'Installation de PyTorch et de ses dépendances (environ 700 Mo)…':
    'Installing PyTorch and its dependencies (about 700 MB)…',
  'Installation du rendu officiel du modèle…': 'Installing the model’s official renderer…',
  "Vérification sur l'exemple du modèle…": 'Checking with the model’s example…',
  Vérification: 'Check',
  "La collecte est incomplète. Consultez l'état des sources dans le catalogue.":
    'Collection is incomplete. Check the sources’ status in the catalog.',
  "uv est requis pour créer l'environnement Python : https://docs.astral.sh/uv/":
    'uv is required to create the Python environment: https://docs.astral.sh/uv/',
  "Le service du modèle local ne s'est pas arrêté. Ses fichiers sont conservés.":
    'The local model service did not stop. Its files are kept.',
  // Fichiers locaux (script de lancement, contrôles de sécurité).
  "Le fichier a été modifié sur le disque depuis son ouverture : rechargez-le avant d'enregistrer.":
    'The file changed on disk since it was opened. Reload it before saving.',
  // Mise à jour depuis une copie locale du dépôt.
  'L’URL du dépôt ne doit pas contenir d’identifiants.':
    'The repository URL must not contain credentials.',
  "Indiquez le dossier du dépôt hindsight-mac (le clone git d'où l'app a été construite).":
    'Choose the hindsight-mac repository folder (the git clone the app was built from).',
  'Ce dossier ne contient pas Hindsight Desktop Tauri.':
    'This folder does not contain Hindsight Desktop Tauri.',
  "Le dépôt n'est sur aucune branche (HEAD détachée).":
    'The repository is not on any branch (detached HEAD).',
  'La compilation a dépassé le délai.': 'The build timed out.',
  'Recherche des opérations en échec…': 'Looking for failed operations…',
  'La politique du dossier mémoire est invalide ; aucun envoi autorisé.':
    'The memory folder policy is invalid; no upload is allowed.',
  'La politique du dossier mémoire est inaccessible ; aucun envoi autorisé.':
    'The memory folder policy cannot be read; no upload is allowed.',
  "Un réglage avancé n'est pas du JSON valide.": 'An advanced setting is not valid JSON.',
  'Adresse de pièce jointe refusée : utilisez HTTPS sans identifiants, ou le serveur configuré.':
    'Attachment address refused: use HTTPS without credentials, or the configured server.',
  "Le script de lancement a changé depuis votre dernière approbation : redémarrez d'abord le serveur depuis Réglages › Serveur.":
    'The launch script changed since your last approval. Restart the server from Settings › Server first.',
  'Démarrage annulé.': 'Start cancelled.',
  'Étiquettes mises à jour.': 'Tags updated.',
  "Changer la portée d'un document demande un serveur Hindsight 1.1.0 ou plus récent.":
    'Changing the scope of a document requires Hindsight server 1.1.0 or later.',
  "Cette banque ne crée pas d'observations : changer la portée n'aurait aucun effet.":
    'This memory bank does not create observations, so changing the scope would have no effect.',
  'Ce document a déjà cette portée.': 'This document already has this scope.',
  partagée: 'shared',
  combinée: 'combined',
  'par étiquette': 'per tag',
  'toutes les combinaisons': 'all combinations',
  'Portée mise à jour.': 'Scope updated.',
  "Journal d'accès activé pour cette banque.": 'Access log enabled for this memory bank.',
  "Journal d'accès désactivé.": 'Access log disabled.',
  "Texte reconstitué à partir des segments : le texte original n'est pas stocké sur le serveur, ce document ne peut donc pas être retraité.":
    'Text rebuilt from chunks: the original text is not stored on the server, so this document cannot be reprocessed.',
  'Aucun texte disponible pour ce document.': 'No text is available for this document.',
  "Choisissez d'abord le script de synchronisation du projet.":
    'Choose the project sync script first.',
  'File d’envoi illisible : réessayez avant de préparer la synchronisation.':
    'The upload queue could not be read. Try again before preparing the sync.',
  'Le script a changé depuis l’aperçu. Relancez la vérification ; rien n’a été envoyé.':
    'The script changed since the preview. Run the check again; nothing was sent.',
  'La file d’envoi est occupée ou illisible : rien n’a été envoyé.':
    'The upload queue is busy or could not be read: nothing was sent.',
  "Le format de ce catalogue n'est pas pris en charge.": 'This catalog format is not supported.',
  'Collecteur illisible.': 'The collector could not be read.',
  'Choisissez un projet et au moins un fichier.': 'Choose a project and at least one file.',
  'Choisissez uniquement des fichiers .md, .tex ou .pdf ordinaires.':
    'Choose only regular .md, .tex or .pdf files.',
  'Un fichier a changé depuis la confirmation. Relancez la demande.':
    'A file changed since the confirmation. Start the request again.',
  'Le dossier ne peut pas être collecté.': 'This folder cannot be collected.',
  'Le dossier a changé depuis la confirmation. Relancez la demande.':
    'The folder changed since the confirmation. Start the request again.',
  'Le collecteur a changé depuis la confirmation. Relancez la demande.':
    'The collector changed since the confirmation. Start the request again.',
  'La collecte a dépassé le délai prévu. Les archives déjà enregistrées sont conservées.':
    'Collection timed out. Archives that were already saved are kept.',
  'Connectez Hindsight pour comparer les versions.': 'Connect Hindsight to compare versions.',
  'Sources collectées. Aucun envoi ni traitement Hindsight.':
    'Sources collected. Nothing was uploaded or processed by Hindsight.',
  'Recherche des régénérations en double…': 'Looking for duplicate regenerations…',
  'Choisissez une banque et ouvrez un catalogue.': 'Choose a memory bank and open a catalog.',
  'Choisissez un catalogue existant.': 'Choose an existing catalog.',
  'Un envoi est encore en cours. Actualisez après son traitement.':
    'An upload is still in progress. Refresh after it has been processed.',
  'Toutes les sources activées sont à jour.': 'All enabled sources are up to date.',
  'Le contexte a changé ; préparez un nouvel aperçu.':
    'The context changed. Prepare a new preview.',
  'Les sources, la sélection ou la banque ont changé. Préparez un nouvel aperçu.':
    'The sources, selection or memory bank changed. Prepare a new preview.',
  'Aucun envoi à vérifier pour cette source.': 'There is no upload to check for this source.',
  'Envoi initial retrouvé ou repris. Actualisez pour vérifier le résultat.':
    'Original upload found or resumed. Refresh to check the result.',
  'Source indisponible ou en attente de revue.': 'Source unavailable or pending review.',
  'Attendez la fin du traitement avant de retirer cette source.':
    'Wait for processing to finish before removing this source.',
  'Source retirée et exclue. Fichier conservé.': 'Source removed and excluded. File kept.',
  'Source locale indisponible.': 'Local source unavailable.',
  'Source hors du dossier du catalogue.': 'Source outside the catalog folder.',
  'Une source TeX ou Markdown est requise pour ce document.':
    'This document needs a TeX or Markdown source.',
  'Le traitement précédent a échoué ou n’a pas enregistré cette version. Une nouvelle validation est nécessaire pour réessayer.':
    'The previous processing failed or did not store this version. Approve it again to retry.',
  'La synchronisation automatique est suspendue : sélectionnez les documents et validez chaque envoi.':
    'Automatic sync is suspended: select the documents and approve each upload.',
  'Le contexte a changé. Actualisez les dossiers avant de préparer l’envoi.':
    'The context changed. Refresh the folders before preparing the upload.',
  'Un fichier a été modifié ou remplacé. Préparez à nouveau l’envoi.':
    'A file was changed or replaced. Prepare the upload again.',
  'Le serveur, les dossiers ou la sélection ont changé. Préparez à nouveau l’envoi.':
    'The server, folders or selection changed. Prepare the upload again.',
  'Les documents ont changé. Actualisez la liste avant de préparer l’envoi.':
    'The documents changed. Refresh the list before preparing the upload.',
  'Les documents ont changé. Actualisez la liste avant de préparer le retrait.':
    'The documents changed. Refresh the list before preparing the removal.',
  'Les documents ont changé depuis la confirmation. Préparez à nouveau le retrait.':
    'The documents changed since the confirmation. Prepare the removal again.',
  'Un fichier source a été retrouvé. Actualisez les dossiers avant de préparer le retrait.':
    'A source file was found again. Refresh the folders before preparing the removal.',
  'Le serveur, les dossiers ou la sélection ont changé. Préparez à nouveau le retrait.':
    'The server, folders or selection changed. Prepare the removal again.',
  'L’envoi a été refusé par le serveur.': 'The server rejected the upload.',
  'Le contexte a changé ; actualisez les sources.': 'The context changed. Refresh the sources.',
  'Configuration mémoire illisible.': 'The memory settings file could not be read.',
  'Politique mémoire incompatible ; envoi suspendu.':
    'Incompatible memory policy; uploads are suspended.',
  'Sélection mémoire illisible ; envoi suspendu.':
    'The memory selection could not be read; uploads are suspended.',
  'Sélection mémoire invalide ; envoi suspendu.':
    'Invalid memory selection; uploads are suspended.',
  'Suivi mémoire invalide ; envoi suspendu.': 'Invalid upload tracking; uploads are suspended.',
  'Cette sélection mémoire appartient à un autre serveur ; envoi suspendu.':
    'This memory selection belongs to another server; uploads are suspended.',
  'Suivi mémoire incomplet ; envoi suspendu.': 'Incomplete upload tracking; uploads are suspended.',
  'Choisissez un dossier et une banque.': 'Choose a folder and a memory bank.',
  'Le contexte a changé ; actualisez la vue.': 'The context changed. Refresh the view.',
  'File d’opérations incomplète ; actualisez avant tout envoi.':
    'Incomplete operations queue. Refresh before uploading.',
  'Identifiants du catalogue invalides ou dupliqués ; envoi suspendu.':
    'Invalid or duplicate catalog IDs; uploads are suspended.',
  'Inventaire Hindsight incomplet.': 'Incomplete Hindsight inventory.',
  'Une source nécessite une revue ou une version texte.':
    'A source needs a review or a text version.',
  'Choisissez une source non liée et un document disponible.':
    'Choose an unlinked source and an available document.',
  'Actualisez les sources de cette banque.': 'Refresh the sources for this memory bank.',
  'Document inconnu.': 'Unknown document.',
  'Des opérations sont encore en cours. Consultez « Activité › Traitements » puis actualisez.':
    'Operations are still running. Check Activity › Processing, then refresh.',
  'Le serveur n’a pas accepté l’envoi. Vérifiez son état avant toute reprise.':
    'The server did not accept the upload. Check its state before retrying.',
  'Le lot initial ne correspond plus à la file locale.':
    'The original batch no longer matches the local queue.',
  'Le lot a changé depuis l’aperçu.': 'The batch changed since the preview.',
  'La sélection ou la politique a changé ; préparez un nouvel aperçu.':
    'The selection or policy changed. Prepare a new preview.',
  'La sélection ou la politique a changé ; actualisez la vue.':
    'The selection or policy changed. Refresh the view.',
  'La politique a changé ; actualisez la vue.': 'The policy changed. Refresh the view.',
  'La version mémorisée a changé ; actualisez la vue.':
    'The stored version changed. Refresh the view.',
  'Le serveur n’a pas confirmé le retrait. La source reste exclue des futurs envois.':
    'The server did not confirm the removal. The source stays excluded from future uploads.',
  'Source hors du dossier suivi.': 'Source outside the tracked folder.',
  'La liste des échecs a changé pendant le chargement. Réessayez.':
    'The list of failures changed while loading. Try again.',
  'Le raccourci du Dock n’a pas pu être enregistré.': 'The Dock shortcut could not be saved.',
  'Redémarrage du service…': 'Restarting the service…',
  'Exécution de la commande…': 'Running the command…',
  "Attente de l'API…": 'Waiting for the API…',
  'Test des LLM…': 'Testing LLMs…',
  'Installation…': 'Installing…',
};

type Rule = [RegExp, (...groups: string[]) => string];

// Nombre déjà formaté par le moteur (séparateurs de la langue du Mac) : seul « 1 » est au singulier.
const count = (n: string, singular: string, plural = `${singular}s`) =>
  `${n.trim()} ${n.replace(/\D/g, '') === '1' ? singular : plural}`;
// Compteurs d'une fusion (« 3 documents ajoutés, 1 document ignoré »), dans l'ordre du moteur.
const mergeCountNames: Record<string, [string, string]> = {
  'document ajouté': ['document added', 'documents added'],
  'documents ajoutés': ['document added', 'documents added'],
  fait: ['fact', 'facts'],
  faits: ['fact', 'facts'],
  observation: ['observation', 'observations'],
  observations: ['observation', 'observations'],
  'modèle mental': ['mental model', 'mental models'],
  'modèles mentaux': ['mental model', 'mental models'],
  'page de connaissance': ['knowledge page', 'knowledge pages'],
  'pages de connaissance': ['knowledge page', 'knowledge pages'],
  'document ignoré': ['skipped document', 'skipped documents'],
  'documents ignorés': ['skipped document', 'skipped documents'],
  'observation ignorée': ['skipped observation', 'skipped observations'],
  'observations ignorées': ['skipped observation', 'skipped observations'],
};
function mergeCounts(counts: string): string {
  return counts
    .split(', ')
    .map((part) => {
      const match = /^([\d\s\u00a0\u202f,.]+) (.+)$/.exec(part);
      const names = match && mergeCountNames[match[2]];
      return names ? count(match[1], names[0], names[1]) : part;
    })
    .join(', ');
}
const toRestore = (banks?: string) => (banks ? ` To restore as soon as possible: ${banks}.` : '');
// Consolidations relancées à la reprise (ou à relancer à la main), insérées avant « À rétablir… ».
const RESTARTED = String.raw`( La consolidation de « .*? » reprend là où la pause l'avait arrêtée\.| Les consolidations reprennent là où la pause les avait arrêtées : .*?\.)?( Consolidation à relancer depuis Mémoire › Consolidation : .*?\.)?`;
const restartedText = (restarted?: string, unrestarted?: string) => {
  let text = '';
  const one = restarted?.match(/^ La consolidation de « (.*) » reprend/);
  const many = restarted?.match(/: (.*)\.$/);
  if (one) text += ` Consolidation of “${one[1]}” picks up where the pause stopped it.`;
  else if (many) text += ` Consolidations pick up where the pause stopped them: ${many[1]}.`;
  const failed = unrestarted?.match(/: (.*)\.$/);
  if (failed) text += ` Consolidation to restart from Memory › Consolidation: ${failed[1]}.`;
  return text;
};
const dashboardParts: Record<string, string> = {
  version: 'version',
  entités: 'entities',
  'série temporelle': 'time series',
  documents: 'documents',
  tags: 'tags',
  échecs: 'failures',
  configuration: 'settings',
  portées: 'scopes',
  consolidations: 'consolidations',
  changements: 'changes',
};
const serverActions: Record<string, string> = {
  démarré: 'Server started',
  redémarré: 'Server restarted',
};

// Messages d’état composés par le moteur. Les noms, identifiants, chemins et erreurs du serveur
// capturés sont réinsérés tels quels. Avant les règles générales (« Échec : … »).
/** États du test des modèles, tels que le moteur les écrit (« injoignable », « clé refusée »…). */
const llmStatus: Record<string, string> = {
  répond: 'responds',
  injoignable: 'unreachable',
  'clé refusée': 'key rejected',
  'aucun fournisseur configuré': 'no provider configured',
};
/** « Extraction des faits (injoignable), Réponses (clé refusée) » : rôles et états traduits un à un. */
function llmFailures(list: string) {
  return list
    .split(/(?<=\)), /)
    .map((item) => {
      const match = /^(.*) \(([^()]*)\)$/.exec(item);
      return match ? `${nativeCatalogText(match[1])} (${llmStatus[match[2]] ?? match[2]})` : item;
    })
    .join(', ');
}

/** Usages du modèle de décision, tels que la page Modèles les nomme. */
const decisionUsage: Record<string, string> = {
  'de la recherche': 'search',
  'des réponses': 'answers',
  'de la consolidation': 'consolidation',
};
/** Noms des réglages de « Comportement de la mémoire », tels que la page les affiche dans chaque langue. */
const memoryLabels: Record<string, string> = {
  'Mission de mémorisation': 'Memory mission',
  "Style d'extraction": 'Extraction style',
  "Instructions d'extraction": 'Extraction instructions',
  'Taille des segments en caractères': 'Chunk size in characters',
  'Conserver le texte des documents': 'Store document text',
  'Autoriser les entités libres': 'Allow free-form entities',
  "Étiquettes d'entités": 'Entity labels',
  'Créer des observations': 'Create observations',
  'Consolider automatiquement': 'Consolidate automatically',
  'Mission de consolidation': 'Consolidation mission',
  "Maximum d'observations par portée": 'Maximum observations per scope',
  'Portée des observations par défaut': 'Default observation scope',
  'Mission de réponse': 'Answer mission',
  'Esprit critique': 'Critical thinking',
  'Interprétation littérale': 'Literal interpretation',
  Empathie: 'Empathy',
  'Recherche textuelle': 'Text search',
  'Recherche temporelle': 'Temporal search',
  'Recherche par relations': 'Relationship search',
  'Réordonner les résultats': 'Rerank results',
  'Écarter les faits inutiles': 'Remove irrelevant facts',
  'Retirer les doublons': 'Remove duplicates',
  'Préférer les observations': 'Prefer observations',
};
/** Ce qui est retiré, dit en tête du dialogue de retrait (« 3 éléments choisis », « Documents sans fichier »). */
function removalTarget(what: string) {
  if (what === 'Documents sans fichier') return 'Documents without a file';
  const chosen = /^([\d\s,.]+) éléments? choisis?$/.exec(what);
  return chosen ? `${count(chosen[1], 'selected item')}` : what;
}
/** Raisons d’un fichier non envoyé, entre parenthèses après son nom. */
function unreadableReasons(list: string) {
  return list
    .replaceAll(
      '(PDF : fournir la source TeX ou Markdown)',
      '(PDF: upload its TeX or Markdown source)',
    )
    .replaceAll('(pas du texte UTF-8)', '(not UTF-8 text)');
}
/** Corps fait de lignes connues, traduites une à une ; les listes (« • ») et les valeurs restent intactes. */
function lineBody(message: string) {
  return message
    .split('\n')
    .map((line) =>
      !line || line.startsWith('• ')
        ? line
        : line.startsWith('Estimation : ')
          ? costSummary(line)
          : nativeSystemMessage(line),
    )
    .join('\n');
}
/** Enregistrement de « Comportement de la mémoire » : « Réglage → valeur », puis les notes. */
function memorySaveBody(message: string) {
  const [changes, ...notes] = message.split('\n\n');
  const value = (shown: string) =>
    shown === '(valeur du serveur)'
      ? '(server value)'
      : shown === 'activé'
        ? 'on'
        : shown === 'désactivé'
          ? 'off'
          : shown;
  const lines = changes.split('\n').map((line) => {
    const match = /^(.+?) → ([\s\S]*)$/.exec(line);
    return match ? `${memoryLabels[match[1]] ?? match[1]} → ${value(match[2])}` : line;
  });
  return [lines.join('\n'), ...notes.map(lineBody)].join('\n\n');
}
/** Enregistrement du script de lancement : « Rôle › Champ : « avant » → « après » », puis la note. */
function scriptSaveBody(message: string) {
  const [changes, ...notes] = message.split('\n\n');
  const value = (shown: string) => (shown === '(non défini)' ? '(not set)' : shown);
  const lines = changes.split('\n').map((line) => {
    if (line === 'Le fichier change (voir le diff).') return exact[line];
    const match = /^(.+?) : (« [\s\S]*? »|\(non défini\)) → (« [\s\S]* »|\(non défini\))$/.exec(
      line,
    );
    if (!match) return line;
    const label = match[1]
      .split(' › ')
      .map((part) => nativeCatalogText(part))
      .join(' › ');
    return `${label}: ${value(match[2])} → ${value(match[3])}`;
  });
  return [lines.join('\n'), ...notes.map(lineBody)].join('\n\n');
}
/** Modification d’une directive : seuls les libellés sont traduits, jamais le nom ni le texte saisis. */
function directiveBody(message: string) {
  let rest = message;
  const tail: string[] = [];
  const activation = /(?:^|\n)(Elle sera réactivée\.|Elle sera désactivée \(conservée\)\.)$/.exec(
    rest,
  );
  if (activation) {
    tail.unshift(
      activation[1] === 'Elle sera réactivée.'
        ? 'It will be turned back on.'
        : 'It will be turned off (kept).',
    );
    rest = rest.slice(0, activation.index);
  }
  const priority = /(?:^|\n)Priorité : (-?\d+)$/.exec(rest);
  if (priority) {
    tail.unshift(`Priority: ${priority[1]}`);
    rest = rest.slice(0, priority.index);
  }
  const head: string[] = [];
  const name = /^Nom : ([^\n]*)(?:\n|$)/.exec(rest);
  if (name) {
    head.push(`Name: ${name[1]}`);
    rest = rest.slice(name[0].length);
  }
  if (rest.startsWith('Contenu : ')) {
    head.push(`Content: ${rest.slice('Contenu : '.length)}`);
    rest = '';
  }
  return rest ? message : [...head, ...tail].join('\n');
}
/** Réglage propre à la banque : la valeur saisie reste telle quelle. */
function overrideBody(message: string) {
  const match =
    /^Nouvelle valeur : ([\s\S]*)\nLe serveur refuse les réglages non surchargeables \(ex\. modèles LLM : voir « Modèles »\)\.$/.exec(
      message,
    );
  return match
    ? `New value: ${match[1]}\nThe server refuses settings that cannot be set per memory bank (for example LLM models: see Models).`
    : message;
}

// Détail d'une erreur composée : souvent un autre message du moteur, traduit à son tour.
const inner = (detail: string) => nativeSystemMessage(detail);
// « banque : erreur ; banque (type) : erreur » : chaque erreur du moteur traduite à part.
function perBankErrors(list: string) {
  return list
    .split(' ; ')
    .map((part) => {
      const at = part.indexOf(' : ');
      return at < 0 ? part : `${part.slice(0, at)}: ${inner(part.slice(at + 3))}`;
    })
    .join('; ');
}
// Réponse du serveur qui ne correspond pas au modèle attendu (champ manquant, type inattendu…).
function decodingProblem(detail: string) {
  let m = /^champ manquant « (.*) » à (.*)$/.exec(detail);
  if (m) return `missing field “${m[1]}” at ${m[2]}`;
  m = /^type inattendu \((.*?)\) à (.*?) : ([\s\S]*)$/.exec(detail);
  if (m) return `unexpected type (${m[1]}) at ${m[2]}: ${m[3]}`;
  m = /^valeur nulle \((.*?)\) à (.*)$/.exec(detail);
  if (m) return `null value (${m[1]}) at ${m[2]}`;
  m = /^JSON invalide à (.*?) : ([\s\S]*)$/.exec(detail);
  if (m) return `invalid JSON at ${m[1]}: ${m[2]}`;
  return detail;
}
const builtAppProblems: Record<string, string> = {
  'exécutable absent': 'executable missing',
  'le dossier de l’app ou son contenu n’est pas un répertoire ordinaire':
    'the app folder or its contents is not a regular directory',
};
function builtAppProblem(detail: string) {
  const identifier = /^identifiant « (.*) » au lieu de « (.*) »$/.exec(detail);
  if (identifier) return `identifier “${identifier[1]}” instead of “${identifier[2]}”`;
  return builtAppProblems[detail] ?? detail;
}

const engineRules: Rule[] = [
  [
    /^Impossible de lister les banques : ([\s\S]*)$/,
    (detail) => `Unable to list memory banks: ${detail}`,
  ],
  [/^([\d\s  .,]+) faits? remis en file\.$/, (n) => `${count(n, 'fact')} requeued.`],
  [/^La banque « (.*) » existe déjà\.$/, (id) => `Memory bank “${id}” already exists.`],
  [/^Création impossible : ([\s\S]*)$/, (detail) => `Could not create the memory bank: ${detail}`],
  [
    /^La banque porte déjà le nom « (.*) »\.$/,
    (name) => `The memory bank is already named “${name}”.`,
  ],
  [/^Banque renommée « (.*) »\.$/, (name) => `Memory bank renamed “${name}”.`],
  [
    /^« (.*) » est déjà l'identifiant d'une autre banque\.$/,
    (alias) => `“${alias}” is already the ID of another memory bank.`,
  ],
  [
    /^« (.*) » s'affiche désormais comme « (.*) »\.$/,
    (bank, alias) => `“${bank}” is now displayed as “${alias}”.`,
  ],
  [
    /^Identifiant changé : « (.*?) »(?: \(« (.*) » y mène encore\))?\.$/,
    (target, old) => `ID changed to “${target}”${old ? ` (“${old}” still leads to it)` : ''}.`,
  ],
  [
    /^Échec : ([\s\S]*)\. Vérifiez l'état des deux banques avant de recommencer\.$/,
    (detail) => `Failed: ${detail}. Check both memory banks before trying again.`,
  ],
  [
    /^Fusion terminée(?: \(([^)]*)\))?(?: ; « (.*?) » (?:mène désormais à « (.*?) »|supprimée))?\.(?: ([\d\s,.]+) faits? (?:attend|attendent) la consolidation de « (.*) » : lancez-la depuis « Mémoire › Consolidation »\.)?$/,
    (counts, source, aliasTarget, waiting, target) =>
      `Merge complete${counts ? ` (${mergeCounts(counts)})` : ''}${source ? (aliasTarget ? `; “${source}” now leads to “${aliasTarget}”` : `; “${source}” deleted`) : ''}.${waiting ? ` ${count(waiting, 'fact')} ${waiting.replace(/\D/g, '') === '1' ? 'is' : 'are'} waiting for consolidation in “${target}”. Run it from Memory › Consolidation.` : ''}`,
  ],
  [
    /^Fusion terminée(?: \(([^)]*)\))?\. « (.*) » est CONSERVÉE : (?:([\d\s,.]+) documents ignorés n'existent|(1) document ignoré n'existe) que dans la source\. Vérifiez, puis supprimez-la depuis « Réglages › Banque »\.$/,
    (counts, source, many, one) =>
      `Merge complete${counts ? ` (${mergeCounts(counts)})` : ''}. “${source}” was KEPT: ${count(many || one, 'skipped document')} ${one ? 'exists' : 'exist'} only in the source. Check, then delete it from Settings › Memory bank.`,
  ],
  [
    /^Fusion faite et « (.*) » supprimée, mais l'alias n'a pas pu être créé : ([\s\S]*)\. Recréez-le depuis « Renommer… »\.$/,
    (source, detail) =>
      `Merge done and “${source}” deleted, but the alias could not be created: ${detail}. Recreate it from Rename….`,
  ],
  [
    /^Échec de la fusion : ([\s\S]*)\. La banque source n'a pas été supprimée\.$/,
    (detail) => `Merge failed: ${detail}. The source memory bank was not deleted.`,
  ],
  [/^« (.*) » mis à jour\.$/, (key) => `“${key}” updated.`],
  [/^Refusé par le serveur : ([\s\S]*)$/, (detail) => `Rejected by the server: ${detail}`],
  [/^Archive prête \((.*)\)\.$/, (size) => `Archive ready (${size}).`],
  [/^Échec de l'export : ([\s\S]*)$/, (detail) => `Export failed: ${detail}`],
  [/^Échec du clonage : ([\s\S]*)$/, (detail) => `Clone failed: ${detail}`],
  [/^Échec de l'import : ([\s\S]*)$/, (detail) => `Import failed: ${detail}`],
  [/^Fichier de modèle invalide : ([\s\S]*)$/, (detail) => `Invalid template file: ${detail}`],
  [/^Échec de la validation : ([\s\S]*)$/, (detail) => `Validation failed: ${detail}`],
  [
    /^([\d\s\u00a0\u202f,.]+) observations? effacées?\.$/,
    (n) => `${count(n, 'observation')} cleared.`,
  ],
  [/^([\d\s\u00a0\u202f,.]+) faits? effacés?\.$/, (n) => `${count(n, 'fact')} cleared.`],
  [
    /^L'opération a échoué : ([\s\S]*)$/,
    (detail) => `The operation failed: ${nativeSystemMessage(detail)}`,
  ],
  [
    /^La banque « (.*) » est en pause : rien n'y est envoyé\. Reprenez-la pour continuer\.$/,
    (bank) => `Memory bank “${bank}” is paused: nothing is sent to it. Resume it to continue.`,
  ],
  [
    /^(?:« (.*?) » est en pause|Toutes les banques sont en pause)\.( Rien n'est envoyé\. Serveur injoignable : la consolidation automatique n'est pas encore coupée \(le bandeau propose de réessayer\)\.)?( La consolidation s'arrête après le lot en cours ; elle reprendra à la reprise\.)?(?: (\d+) consolidations s'arrêtent après leur lot en cours ; elles reprendront à la reprise\.)?(?: ([\d\s,.]+) régénérations? de connaissances? annulées?\.)?(?: Consolidation automatique pas encore coupée pour (.*) \(le bandeau propose de réessayer\)\.)?$/,
    (bank, unreachable, oneStopped, manyStopped, cancelled, failures) =>
      (bank ? `“${bank}” is paused.` : 'All memory banks are paused.') +
      (unreachable
        ? ' Nothing is sent. The server is unreachable, so automatic consolidation is not turned off yet (the banner offers to try again).'
        : '') +
      (oneStopped
        ? ' The consolidation stops after its current batch and picks up again on resume.'
        : '') +
      (manyStopped
        ? ` ${manyStopped} consolidations stop after their current batch and pick up again on resume.`
        : '') +
      (cancelled ? ` ${count(cancelled, 'knowledge regeneration')} cancelled.` : '') +
      (failures
        ? ` Automatic consolidation is not turned off yet for ${failures} (the banner offers to try again).`
        : ''),
  ],
  [/^Toujours en échec : (.*)\.$/, (failures) => `Still failing: ${failures}.`],
  [/^Impossible de lister la file : ([\s\S]*)$/, (detail) => `Unable to list the queue: ${detail}`],
  [
    /^Aucune régénération de connaissance en double(?: dans « (.*) »)?\.$/,
    (bank) => `No duplicate knowledge regenerations${bank ? ` in “${bank}”` : ''}.`,
  ],
  [/^« (.*) » est déjà en pause\.$/, (bank) => `“${bank}” is already paused.`],
  [/^« (.*) » n'est pas en pause\.$/, (bank) => `“${bank}” is not paused.`],
  [
    /^« (.*) » n'est en pause qu'avec toutes les banques : reprenez toutes les banques\.$/,
    (bank) =>
      `“${bank}” is paused only through the pause on all memory banks. Resume all memory banks.`,
  ],
  [
    /^Aucune pause sur toutes les banques\. En pause une à une : (.*)\.$/,
    (banks) => `There is no pause on all memory banks. Paused one by one: ${banks}.`,
  ],
  [/^Mettre « (.*) » en pause \?$/, (bank) => `Pause “${bank}”?`],
  [
    /^Une régénération de « (.*) » est déjà en cours ou en file\.$/,
    (name) => `A regeneration of “${name}” is already running or queued.`,
  ],
  [
    /^Régénération de « (.*) » mise en file : suivi dans « Activité › Traitements »\.$/,
    (name) => `Regeneration of “${name}” queued. Follow it in Activity › Processing.`,
  ],
  [
    /^Question de « (.*) » modifiée ; régénération mise en file : suivi dans « Activité › Traitements »\.$/,
    (name) =>
      `Question of “${name}” changed. Its regeneration is queued: follow it in Activity › Processing.`,
  ],
  [
    /^Question enregistrée, mais la régénération n'a pas pu partir : ([\s\S]*) Utilisez « Régénérer »\.$/,
    (detail) =>
      `Question saved, but the regeneration could not start: ${nativeSystemMessage(detail)} Use “Regenerate”.`,
  ],
  [
    /^Consolidation automatique pas encore coupée pour (.*) \((.*)\)\.$/,
    (bank, detail) =>
      `Automatic consolidation is not turned off yet for ${bank} (${nativeSystemMessage(detail)}).`,
  ],
  [/^Reprendre « (.*) » \?$/, (bank) => `Resume “${bank}”?`],
  [
    new RegExp(
      String.raw`^« (.*?) » reprend : sa consolidation automatique retrouve son réglage d'avant la pause\.` +
        RESTARTED +
        String.raw`(?: À rétablir dès que possible : (.*)\.)?$`,
    ),
    (bank, restarted, unrestarted, restore) =>
      `“${bank}” resumes: automatic consolidation returns to its setting from before the pause.${restartedText(restarted, unrestarted)}${toRestore(restore)}`,
  ],
  [
    new RegExp(
      String.raw`^Toutes les banques reprennent : la consolidation automatique retrouve son réglage d'avant la pause\.(?: Restent en pause : (.*?)\.)?` +
        RESTARTED +
        String.raw`(?: À rétablir dès que possible : (.*)\.)?$`,
    ),
    (paused, restarted, unrestarted, restore) =>
      `All memory banks resume: automatic consolidation returns to its setting from before the pause.${paused ? ` Still paused: ${paused}.` : ''}${restartedText(restarted, unrestarted)}${toRestore(restore)}`,
  ],
  [
    new RegExp(
      String.raw`^Toutes les banques reprennent\.` +
        RESTARTED +
        String.raw`(?: À rétablir dès que possible : (.*)\.)?$`,
    ),
    (restarted, unrestarted, restore) =>
      `All memory banks resume.${restartedText(restarted, unrestarted)}${toRestore(restore)}`,
  ],
  [
    /^Aucune opération en attente dans « (.*) »\.$/,
    (bank) => `No pending operations in “${bank}”.`,
  ],
  [
    /^([\d\s,.]+) opérations? annulées?(?:\.|, ([\d\s,.]+) non annulées? : ([\s\S]*))$/,
    (n, failed, detail) =>
      `${count(n, 'operation')} cancelled${failed ? `, ${failed.trim()} not cancelled: ${detail}` : '.'}`,
  ],
  [/^Le test des LLM n'a pas abouti : ([\s\S]*)$/, (detail) => `The LLM test failed: ${detail}`],
  [
    /^Modèle de décision (de la recherche|des réponses|de la consolidation) : l'URL Cloud hériterait de la clé du modèle local\. Choisissez l'URL locale ou une clé propre à cet usage avant d'enregistrer\.$/,
    (usage) =>
      `Decision model for ${decisionUsage[usage]}: the Cloud URL would inherit the local model’s key. Choose the local URL or a key specific to this use before saving.`,
  ],
  [
    /^Modèle de décision (de la recherche|des réponses|de la consolidation) sur Hindsight Cloud : connectez le compte ou configurez (\S+)\. Pour un modèle local, choisissez l'URL de ce Mac\.$/,
    (usage, key) =>
      `Decision model for ${decisionUsage[usage]} on Hindsight Cloud: connect the account or configure ${key}. For a local model, choose this Mac’s URL.`,
  ],
  [
    /^Redémarrage refusé : ([\s\S]*)$/,
    (detail) => `Restart refused: ${nativeSystemMessage(detail)}`,
  ],
  [/^La commande a échoué \(code (-?\d+)\)\.$/, (code) => `The command failed (code ${code}).`],
  [
    /^Impossible d'exécuter la commande : ([\s\S]*)$/,
    (detail) => `Unable to run the command: ${detail}`,
  ],
  [
    /^L'API ne répond pas après (\d+) s\. Consultez la sortie ci-dessous et les journaux du serveur\.$/,
    (seconds) =>
      `The API is not responding after ${seconds} s. Check the output below and the server logs.`,
  ],
  [
    /^Serveur redémarré, mais la vérification des LLM a échoué : ([\s\S]*)$/,
    (detail) => `Server restarted, but the LLM check failed: ${detail}`,
  ],
  [
    /^L'historique local a divergé de (.*) : mettez à jour à la main\.$/,
    (remote) => `Local history has diverged from ${remote}. Update manually.`,
  ],
  [
    /^Impossible d'utiliser ce script : ([\s\S]*)$/,
    (detail) => `Unable to use this script: ${nativeSystemMessage(detail)}`,
  ],
  [/^Démarrage refusé : ([\s\S]*)$/, (detail) => `Start refused: ${nativeSystemMessage(detail)}`],
  [
    /^Serveur (démarré|redémarré) : l'API répond\.$/,
    (action) => `${serverActions[action]}: the API is responding.`,
  ],
  [
    /^Comportement enregistré \(([\d\s,.]+) réglages?\)\.$/,
    (n) => `Memory structure saved (${count(n, 'setting')}).`,
  ],
  [
    /^Impossible de préparer la relance : ([\s\S]*)$/,
    (detail) => `Unable to prepare the retry: ${detail}`,
  ],
  [
    /^Relance interrompue : ([\d\s,.]+) opérations? remises? en file\.$/,
    (n) => `Retry interrupted: ${count(n, 'operation')} requeued.`,
  ],
  [/^([\d\s,.]+) opérations? relancées?\.$/, (n) => `${count(n, 'operation')} retried.`],
  [
    /^([\d\s,.]+) opérations? relancées?, ([\d\s,.]+) refusées? : ([\s\S]*)$/,
    (n, refused, detail) =>
      `${count(n, 'operation')} retried, ${refused.trim()} refused: ${detail}`,
  ],
  [
    /^Document supprimé \(([\d\s,.]+) faits?\)\.$/,
    (n) => `Document deleted (${count(n, 'fact')}).`,
  ],
  [
    /^Recherche des échecs : ([\d\s,.]+) trouvés?…$/,
    (n) => `Looking for failures: ${n.trim()} found…`,
  ],
  [/^Script illisible : ([\s\S]*)$/, (path) => `The script could not be read: ${path}`],
  [
    /^Ce script n'écrit pas dans la banque « (.*) » : rien n'est lancé\.$/,
    (bank) => `This script does not write to memory bank “${bank}”: nothing was started.`,
  ],
  [
    /^La banque traite encore ([\d\s,.]+) envois? : attendez la fin, sinon les mêmes documents seraient renvoyés et payés deux fois\.$/,
    (n) =>
      `The memory bank is still processing ${count(n, 'upload')}. Wait for it to finish, otherwise the same documents would be sent and paid for twice.`,
  ],
  [/^Aperçu impossible : ([\s\S]*)$/, (detail) => `Preview failed: ${detail}`],
  [
    /^Aperçu impossible( \(délai dépassé\))? :\n([\s\S]*)$/,
    (timedOut, output) => `Preview failed${timedOut ? ' (timed out)' : ''}:\n${output}`,
  ],
  [
    /^Rien à envoyer : la banque est à jour(?:\.| ; ([\d\s,.]+) documents? sans source en mémoire, rien n'est supprimé\.)$/,
    (orphans) =>
      `Nothing to send: the memory bank is up to date${orphans ? `; ${count(orphans, 'document')} without a source in memory, nothing is deleted.` : '.'}`,
  ],
  [
    /^([\s\S]*) La banque les traite maintenant \(voir « Activité › Traitements »\)\.$/,
    (sent) =>
      `${sent === 'Envoi terminé.' ? 'Upload complete.' : sent} The memory bank is processing them now (see Activity › Processing).`,
  ],
  [
    /^Échec de l'envoi( \(délai dépassé\))? :\n([\s\S]*)$/,
    (timedOut, output) => `Upload failed${timedOut ? ' (timed out)' : ''}:\n${output}`,
  ],
  [/^Échec de l'envoi : ([\s\S]*)$/, (detail) => `Upload failed: ${detail}`],
  [/^Catalogue illisible : ([\s\S]*)$/, (detail) => `The catalog could not be read: ${detail}`],
  [/^Fichier inaccessible : ([\s\S]*)$/, (detail) => `File unavailable: ${detail}`],
  [
    /^([\d\s,.]+) documents? ajoutés? ou mis à jour, ([\d\s,.]+) déjà à jour\. Aucun traitement Hindsight\.$/,
    (added, unchanged) =>
      `${count(added, 'document')} added or updated, ${unchanged} already up to date. Nothing was processed by Hindsight.`,
  ],
  [/^Collecte impossible : ([\s\S]*)$/, (detail) => `Collection failed: ${detail}`],
  [
    /^Serveur redémarré, mais : ([\s\S]*)$/,
    (detail) => `Server restarted, but: ${llmFailures(detail)}`,
  ],
  [/^Les (\d+) rôles LLM testés répondent\.$/, (n) => `All ${n} tested LLM roles respond.`],
  [
    /^Rôles? LLM en échec : ([\s\S]*)\.$/,
    (list) =>
      `${list.includes('), ') ? 'Failing LLM roles' : 'Failing LLM role'}: ${llmFailures(list)}.`,
  ],
  [
    /^Source remplacée ou non ordinaire : ([\s\S]*)$/,
    (path) => `Source replaced or not a regular file: ${path}`,
  ],
  [
    /^Source hors des dossiers suivis : ([\s\S]*)$/,
    (path) => `Source outside tracked folders: ${path}`,
  ],
  [/^Le chemin de la source a changé : ([\s\S]*)$/, (path) => `The source path changed: ${path}`],
  [
    /^Source hors du dossier suivi : ([\s\S]*)$/,
    (path) => `Source outside the tracked folder: ${path}`,
  ],
  [
    /^Le fichier a changé pendant la lecture : ([\s\S]*)$/,
    (path) => `The file changed while it was being read: ${path}`,
  ],
  [
    /^([\d\s,.]+) sources? envoyées? ; traitement à suivre dans cette liste\.$/,
    (n) => `${count(n, 'source')} uploaded. Follow processing in this list.`,
  ],
  [/^Relecture impossible : ([\s\S]*)$/, (detail) => `Reload failed: ${detail}`],
  [
    /^Aucun fichier lisible parmi la sélection : ([\s\S]*)$/,
    (files) => `No readable files in the selection: ${unreadableReasons(files)}`,
  ],
  [
    /^([\d\s,.]+) fichiers? → banque « (.*) » : ([\d\s,.]+) en texte, ([\d\s,.]+) à convertir par le serveur \(HTML, Office\)\.$/,
    (n, bank, text, converted) =>
      `${count(n, 'file')} → memory bank “${bank}”: ${text.trim()} as text, ${converted.trim()} to be converted by the server (HTML, Office).`,
  ],
  [
    /^≈ ([\d\s,.]+) jetons envoyés au LLM d'extraction \(estimation grossière pour les fichiers convertis\)\.$/,
    (n) => `≈ ${n.trim()} tokens sent to the extraction LLM (rough estimate for converted files).`,
  ],
  [
    /^([\d\s,.]+) documents existants seront REMPLACÉS : leurs faits sont supprimés puis réextraits\.$/,
    (n) =>
      `${n.trim()} existing documents will be REPLACED: their facts are deleted and extracted again.`,
  ],
  [/^Non envoyés : ([\s\S]*)$/, (files) => `Not uploaded: ${unreadableReasons(files)}`],
  [
    /^([\d\s,.]+) fichiers? sur ([\d\s,.]+) mis en file d'extraction dans « (.*?) » \(([\d\s,.]+) opérations?\)\.(?: Refusés : ([\s\S]*))?$/,
    (sent, total, bank, operations, rejected) =>
      `${sent.trim()} of ${count(total, 'file')} queued for extraction in “${bank}” (${count(operations, 'operation')}).${rejected ? ` Rejected: ${rejected}` : ''}`,
  ],
  [
    /^Ces réglages deviennent propres à la banque « (.*) »\.$/,
    (bank) => `These settings become specific to memory bank “${bank}”.`,
  ],
  [
    /^(Esprit critique|Interprétation littérale|Empathie) : choisissez une valeur de 1 à 5\.$/,
    (label) => `${memoryLabels[label]}: choose a value from 1 to 5.`,
  ],
  [/^Vérification impossible : ([\s\S]*)$/, (detail) => `Check failed: ${detail}`],
  [
    /^([\d\s,.]+) documents? retirés? sur ([\d\s,.]+) de « (.*?) »\.(?: Échecs : ([\s\S]*))?$/,
    (removed, total, bank, failures) =>
      `${count(removed, 'document')} of ${total.trim()} removed from “${bank}”.${failures ? ` Failures: ${failures}` : ''}`,
  ],
  [
    /^(version|entités|série temporelle|documents|tags|échecs|configuration|portées|consolidations|changements) : ([\s\S]*)$/,
    (part, detail) => `${dashboardParts[part]}: ${detail}`,
  ],
];

const rules: Rule[] = [
  [
    /^Hindsight Cloud : connectez votre compte ou configurez (.*)\. Pour un modèle local, choisissez « Sur ce Mac »\.$/,
    (key) =>
      `Hindsight Cloud: connect your account or configure ${key}. For a local model, choose “On this Mac”.`,
  ],
  [/^Démarrage impossible : ([\s\S]*)$/, (detail) => `Startup failed: ${inner(detail)}`],
  [/^Installation impossible : ([\s\S]*)$/, (detail) => `Installation failed: ${inner(detail)}`],
  [
    /^Désinstallation impossible : ([\s\S]*)$/,
    (detail) => `Uninstallation failed: ${inner(detail)}`,
  ],
  [/^Arrêt impossible : ([\s\S]*)$/, (detail) => `Stop failed: ${inner(detail)}`],
  [
    /^Le service ne s'est pas arrêté dans les ([\d\s,.]+) s\.$/,
    (n) => `The service did not stop within ${n.trim()} s.`,
  ],
  [
    /^L'API répond, mais le nouveau processus du service n'est pas prêt(?: \(code de sortie (-?\d+)\))?\. Consultez le journal ci-dessous\.$/,
    (code) =>
      `The API responds, but the service’s new process is not ready${code ? ` (exit code ${code})` : ''}. See the log below.`,
  ],
  [
    /^Le service a été lancé mais l'API ne répond pas(?: \(code de sortie (-?\d+)\))?\. Consultez le journal ci-dessous\.$/,
    (code) =>
      `The service was started but the API does not respond${code ? ` (exit code ${code})` : ''}. See the log below.`,
  ],
  [
    /^launchctl (\S+) a échoué(?: : ([\s\S]*)|\.)$/,
    (verb, detail) => `launchctl ${verb} failed${detail ? `: ${detail}` : '.'}`,
  ],
  [/^Impossible de créer le journal (.*)$/, (path) => `Could not create the log ${path}`],
  [
    /^Écriture de (.*) impossible : ([\s\S]*)$/,
    (path, detail) => `Could not write ${path}: ${detail}`,
  ],
  [/^Écriture de (.*) impossible\.$/, (path) => `Could not write ${path}.`],
  [
    /^Lecture du service local impossible : ([\s\S]*)$/,
    (detail) => `Could not read the local service: ${detail}`,
  ],
  [
    /^Arrêt du modèle local impossible : ([\s\S]*)$/,
    (detail) => `Could not stop the local model: ${detail}`,
  ],
  [
    /^Téléchargement du modèle (\S+) \(([\d,.]+) Go\)…$/,
    (model, size) => `Downloading the ${model} model (${size.replace(',', '.')} GB)…`,
  ],
  [/^([\s\S]+?) : délai dépassé\.$/, (step) => `${inner(step)}: timed out.`],
  [
    /^([\s\S]+?) : échec \(code (-?\d+)\)\. Voir le journal\.$/,
    (step, code) => `${inner(step)}: failed (code ${code}). See the log.`,
  ],
  [
    /^Le serveur local ne répond pas : voir (.*)\.$/,
    (path) => `The local server does not respond. See ${path}.`,
  ],
  [/^Fichier introuvable : (.*)$/, (path) => `File not found: ${path}`],
  [/^Erreur d'écriture : ([\s\S]*)$/, (detail) => `Write error: ${detail}`],
  [/^(.*) n'est pas un fichier ordinaire\.$/, (path) => `${path} is not a regular file.`],
  [/^(.*) appartient à un autre utilisateur\.$/, (path) => `${path} belongs to another user.`],
  [
    /^(.*) est modifiable par d'autres comptes \(corrigez avec chmod go-w\)\.$/,
    (path) => `${path} is writable by other accounts (fix with chmod go-w).`,
  ],
  [
    /^Le dossier (.*) est modifiable par d'autres comptes : le script pourrait y être remplacé\.$/,
    (path) =>
      `The folder ${path} is writable by other accounts: the script could be replaced there.`,
  ],
  [
    /^(.*) n'est pas exécutable \(chmod u\+x\)\.$/,
    (path) => `${path} is not executable (chmod u+x).`,
  ],
  [
    /^Le dépôt distant \((.*)\) utilise un transport non chiffré : passez en https:\/\/ ou ssh\.$/,
    (url) =>
      `The remote repository (${url}) uses an unencrypted transport. Switch to https:// or ssh.`,
  ],
  [
    /^Transport du dépôt distant non pris en charge pour les mises à jour : (.*)$/,
    (url) => `Remote repository transport not supported for updates: ${url}`,
  ],
  [/^(.*) n'est pas un dépôt git\.$/, (path) => `${path} is not a git repository.`],
  [
    /^(.*) ne contient pas le projet hindsight-mac\.$/,
    (path) => `${path} does not contain the hindsight-mac project.`,
  ],
  [
    /^git (\S+) a échoué(?: : ([\s\S]*)|\.)$/,
    (verb, detail) => `git ${verb} failed${detail ? `: ${detail}` : '.'}`,
  ],
  [/^Nom de branche inattendu : (.*)$/, (name) => `Unexpected branch name: ${name}`],
  [/^Nom de dépôt distant inattendu : (.*)$/, (name) => `Unexpected remote name: ${name}`],
  [
    /^La compilation a échoué \(code (-?\d+)\) : voir le journal\.$/,
    (code) => `The build failed (code ${code}). See the log.`,
  ],
  [
    /^Application construite invalide : ([\s\S]*)$/,
    (detail) => `Invalid built app: ${builtAppProblem(detail)}`,
  ],
  [
    /^Copie impossible dans (.*) : ([\s\S]*)$/,
    (path, detail) => `Could not copy into ${path}: ${detail}`,
  ],
  [
    /^Impossible de remplacer le contenu de l’app : ([\s\S]*)$/,
    (detail) => `Could not replace the app’s contents: ${detail}`,
  ],
  [
    /^Impossible de sauvegarder l’ancienne version : ([\s\S]*)$/,
    (detail) => `Could not back up the previous version: ${detail}`,
  ],
  [
    /^Installation interrompue\. Ancienne version conservée dans (.*) : ([\s\S]*)$/,
    (path, detail) => `Installation interrupted. Previous version kept in ${path}: ${detail}`,
  ],
  [
    /^Impossible d[’']installer la nouvelle version : ([\s\S]*)$/,
    (detail) => `Could not install the new version: ${detail}`,
  ],
  [
    /^Impossible de déplacer l'ancienne version : ([\s\S]*)$/,
    (detail) => `Could not move the previous version: ${detail}`,
  ],
  [/^Traces illisibles pour ([\s\S]*)$/, (list) => `Unreadable traces for ${perBankErrors(list)}`],
  [
    /^Relevé des services incomplet : ([\s\S]*)$/,
    (list) => `Incomplete service usage: ${perBankErrors(list)}`,
  ],
  [
    /^Ajout incomplet : Consultez l’état des documents dans le catalogue\.$/,
    () => 'Incomplete import. Check the documents’ status in the catalog.',
  ],
  [/^Ajout incomplet : ([\s\S]*)$/, (detail) => `Incomplete import: ${detail}`],
  [/^Relance : ([\d\s,.]+) sur ([\d\s,.]+)…$/, (i, n) => `Retrying: ${i.trim()} of ${n.trim()}…`],
  [
    /^Sélection refusée : source archivée ou en attente de revue\.\n([\s\S]*)$/,
    (list) => `Selection refused: source archived or pending review.\n${list}`,
  ],
  [/^(.*?) : (git \S+ a échoué[\s\S]*)$/, (repo, detail) => `${repo}: ${inner(detail)}`],
  [
    /^Clé d'étiquette invalide « (.*) » \(non vide, sans espace\)\.$/,
    (key) => `Invalid label key “${key}” (must not be empty or contain spaces).`,
  ],
  [/^Clé d'étiquette en double : (.*)\.$/, (key) => `Duplicate label key: ${key}.`],
  [
    /^L'étiquette « (.*) » de type (\S+) n'a aucune valeur permise\.$/,
    (key, type) => `Label “${key}” of type ${type} has no allowed values.`,
  ],
  [
    /^Le serveur renvoie une adresse de téléchargement hors de (\S+) : (.*)$/,
    (base, url) => `The server returned a download address outside ${base}: ${url}`,
  ],
  // Colonne « Lecteur » du journal d'accès (transport · identité).
  [
    /^(\S+) · client non identifié \(profil (.*)\)$/,
    (transport, profile) => `${transport} · unidentified client (profile ${profile})`,
  ],
  [/^(\S+) · appelant non identifié$/, (transport) => `${transport} · unidentified caller`],
  [/^(\S+) · \(sans (.*)\)$/, (transport, key) => `${transport} · (no ${key})`],
  [
    /^Ce dossier est rattaché à la banque « (.*) »\. Sélectionnez-la pour envoyer ou retirer ses sources\.$/,
    (bank) =>
      `This folder belongs to the “${bank}” memory bank. Select it to upload or remove its sources.`,
  ],
  [/^Redémarrage impossible : ([\s\S]*)$/, (detail) => `Restart failed: ${inner(detail)}`],
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
  [/^Effacer TOUS les faits de « (.*) » \?$/, (id) => `Clear ALL facts from “${id}”?`],
  [
    /^Effacer tous les faits « (.*) » de « (.*) » \?$/,
    (type, id) => `Clear all “${type}” facts from “${id}”?`,
  ],
  [
    /^Effacer toutes les observations de « (.*) » \?$/,
    (id) => `Clear all observations from “${id}”?`,
  ],
  [/^Modifier « (.*) » pour cette banque \?$/, (key) => `Change “${key}” for this memory bank?`],
  [/^Créer la directive « (.*) » \?$/, (name) => `Create directive “${name}”?`],
  [/^Modifier la directive « (.*) » \?$/, (name) => `Edit directive “${name}”?`],
  [/^Supprimer la directive « (.*) » \?$/, (name) => `Delete directive “${name}”?`],
  [/^Créer le modèle mental « (.*) » \?$/, (name) => `Create mental model “${name}”?`],
  [/^Régénérer « (.*) » \?$/, (name) => `Regenerate “${name}”?`],
  [/^Modifier la question de « (.*) » \?$/, (name) => `Change the question of “${name}”?`],
  [/^Renommer le modèle mental « (.*) » \?$/, (name) => `Rename mental model “${name}”?`],
  [/^Renommer la page de connaissance « (.*) » \?$/, (name) => `Rename knowledge page “${name}”?`],
  [/^Supprimer le modèle mental « (.*) » \?$/, (name) => `Delete mental model “${name}”?`],
  [/^Supprimer la page de connaissance « (.*) » \?$/, (name) => `Delete knowledge page “${name}”?`],
  [/^Cloner « (.*) » vers « (.*) » \?$/, (source, target) => `Clone “${source}” into “${target}”?`],
  [/^Importer l'archive dans « (.*) » \?$/, (id) => `Import the archive into “${id}”?`],
  [/^Appliquer le gabarit à « (.*) » \?$/, (id) => `Apply the template to “${id}”?`],
  [/^Envoyer à « (.*) » \?$/, (id) => `Upload to “${id}”?`],
  [
    /^Retirer ([\d\s,.]+) documents? de « (.*) » \?$/,
    (n, id) => `Remove ${count(n, 'document')} from “${id}”?`,
  ],
  [/^Ajouter ([\d\s,.]+) documents? \?$/, (n) => `Add ${count(n, 'document')}?`],
  [/^Passer la portée en « (.*) » \?$/, (scope) => `Change scope to “${scopeLabel(scope)}”?`],
  [/^étiquettes : (.*)$/, (sets) => `tags: ${sets}`],
  [
    /^Relancer ([\d\s,.]+) opérations? échouées? \?$/,
    (n) => `Retry ${count(n, 'failed operation')}?`,
  ],
  [
    /^Annuler ([\d\s,.]+) opérations? en attente \?$/,
    (n) => `Cancel ${count(n, 'pending operation')}?`,
  ],
  [
    /^Annuler ([\d\s,.]+) régénérations? en double \?$/,
    (n) => `Cancel ${count(n, 'duplicate regeneration')}?`,
  ],
  [/^Activer le journal d'accès pour « (.*) » \?$/, (id) => `Enable the access log for “${id}”?`],
  [
    /^Désactiver le journal d'accès pour « (.*) » \?$/,
    (id) => `Disable the access log for “${id}”?`,
  ],
  [/^Connecter (.*) \?$/, (name) => `Connect ${name}?`],
  [/^Se déconnecter de (.*) \?$/, (name) => `Disconnect from ${name}?`],
  [/^Restaurer (.*) \?$/, (name) => `Restore ${name}?`],
  [/^Serveur injoignable : ([\s\S]*)$/, (detail) => `Server unreachable: ${detail}`],
  [/^URL invalide : ([\s\S]*)$/, (detail) => `Invalid URL: ${detail}`],
  [/^HTTP (\d+) sur ([\s\S]*)$/, (status, detail) => `HTTP ${status} at ${detail}`],
  [
    /^Réponse inattendue pour (.*?) : ([\s\S]*)$/,
    (path, detail) => `Unexpected response for ${path}: ${decodingProblem(detail)}`,
  ],
  [/^Réponse inattendue pour ([\s\S]*)$/, (detail) => `Unexpected response for ${detail}`],
  [/^Échec : ([\s\S]*)$/, (detail) => `Failed: ${nativeSystemMessage(detail)}`],
  [/^Action inconnue : (.*)$/, (action) => `Unknown action: ${action}`],
  [/^Application construite : (.*)$/, (path) => `Application built: ${path}`],
  [/^Banque « (.*) » créée\.$/, (id) => `Memory bank “${id}” created.`],
  [
    /^Banque « (.*) » créée, mais sa mission n'a pas été enregistrée : ([\s\S]*)$/,
    (id, detail) => `Memory bank “${id}” created, but its mission was not saved: ${detail}`,
  ],
  [
    /^Clés non prises en charge ici : (.*)\. Modifiez-les dans Réglages › Banque › Configuration avancée de la banque\.$/,
    (keys) =>
      `Keys not supported here: ${keys}. Change them in Settings › Memory bank › Advanced bank configuration.`,
  ],
  [
    /^Le serveur a refusé \(([\s\S]*)\)\. Pour l'activer côté serveur : ajouter `([A-Z0-9_]+)=true` à l'environnement du processus Hindsight, puis le redémarrer\.$/,
    (detail, name) =>
      `The server refused (${nativeSystemMessage(detail)}). To enable it on the server, add \`${name}=true\` to the Hindsight process environment, then restart it.`,
  ],
];

// Libellé de portée venu du moteur (« partagée », « étiquettes : a + b », « inconnue »).
function scopeLabel(label: string): string {
  if (label === 'inconnue') return 'unknown';
  return nativeSystemMessage(label);
}

export function nativeSystemMessage(message: string): string {
  if (getLanguage() !== 'en') return message;
  if (Object.hasOwn(exact, message)) return exact[message];
  for (const list of [engineRules, rules])
    for (const [pattern, render] of list) {
      const match = pattern.exec(message);
      if (match) return render(...match.slice(1));
    }
  return message;
}

// Raisons affichées par source dans le catalogue (`memory.reason`, jusqu’à ~20 000 lignes) :
// traduites à l’affichage plutôt que recopiées dans l’instantané.
const sourceReasons: Record<string, string> = {
  'En attente de revue': 'Pending review',
  'Retrait validé': 'Removal approved',
  'Source contenant des documents retirés ou en attente de revue':
    'Source containing removed documents or documents pending review',
  "Document de la banque qu'aucune source du catalogue ne décrit":
    'Memory bank document that no catalog source describes',
  'Commit déjà classé hors mémoire': 'Commit already classified as outside memory',
};

export function nativeSourceReason(text: unknown): string {
  if (typeof text !== 'string') return '';
  if (getLanguage() !== 'en') return text;
  return Object.hasOwn(sourceReasons, text) ? sourceReasons[text] : nativeSystemMessage(text);
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
  "Le nouveau texte sera ré-indexé ; les observations et liens qui en dérivent sont supprimés. Cette banque ne crée pas d'observations : elles ne seront pas recréées.\n\nL'ancienne version reste dans l'archive de curation du serveur.":
    'The new text will be reindexed. Derived observations and links will be deleted. This memory bank does not create observations, so they will not be recreated.\n\nThe previous version remains in the server’s curation archive.',
  "Le serveur exige le texte avec toute correction : il sera ré-indexé tel quel.\n\nL'ancienne version reste dans l'archive de curation du serveur.":
    'The server requires text with every edit: it will be reindexed as-is.\n\nThe previous version remains in the server’s curation archive.',
  'Les faits sont conservés ; les observations seront recréées par une nouvelle consolidation (appels LLM).':
    'Facts are kept. Observations will be recreated through a new consolidation (LLM calls).',
  "Les faits sont conservés. Cette banque ne crée pas d'observations : elles ne seront pas recréées tant que « Créer des observations » reste désactivé.":
    'Facts are kept. This memory bank does not create observations, so they will not be recreated while Create observations stays turned off.',
  "Irréversible. Les documents restent, mais leurs faits disparaissent. Exportez la banque d'abord.":
    'Irreversible. Documents remain, but their facts are deleted. Export the memory bank first.',
  "Faits, documents, entités, observations, configuration : tout est supprimé, sans retour possible. Exportez-la d'abord.":
    'Facts, documents, entities, observations and settings will all be permanently deleted. Export the memory bank first.',
  "La banque revient aux valeurs globales du serveur (missions, disposition, réglages d'extraction et de recherche…).":
    'The memory bank returns to the server’s global settings (missions, disposition, extraction and search settings…).',
  "Il sera exclu de la recherche et de la consolidation ; ses liens et observations dérivées sont retirés. C'est réversible (« Rétablir »).":
    'It will be excluded from search and consolidation. Its derived links and observations will be removed. You can reverse this with Restore.',
  'Il redevient visible de la recherche et sera reconsolidé.':
    'It will appear in search again and be consolidated again.',
  'Il redevient visible de la recherche.': 'It will appear in search again.',
  'Les observations qui en dérivent sont supprimées ; elles pourront être recréées par la prochaine consolidation.':
    'Derived observations will be deleted. The next consolidation can recreate them.',
  "Les observations qui en dérivent sont supprimées. Cette banque ne crée pas d'observations : elles ne seront pas recréées.":
    'Derived observations will be deleted. This memory bank does not create observations, so they will not be recreated.',
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
    .replace("mesurée sur l'essai à blanc", 'measured from the dry run');
}

const messageRules: Array<[RegExp, Rule]> = [
  [/^Envoyer à « .* » \?$/, [/^([\s\S]*)$/, (body) => lineBody(body)]],
  [
    /^Enregistrer le comportement de la mémoire \?$/,
    [/^([\s\S]*)$/, (body) => memorySaveBody(body)],
  ],
  [/^Enregistrer le script de lancement \?$/, [/^([\s\S]*)$/, (body) => scriptSaveBody(body)]],
  [
    /^Essai à blanc de l'extraction \?$/,
    [
      /^Le LLM d'extraction lit ([\d\s  .,]+) caractères avec les réglages du brouillon\. Rien n'est enregistré dans la banque\.(?:\n\n([^\n]*))?$/,
      (n, cost) =>
        `The extraction LLM reads ${n.trim()} characters with the draft settings. Nothing is saved to the memory bank.${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Enregistrer les plafonds \?$/,
    [
      /^Budget quotidien : (.*)\nAu dépassement : (.*)\.$/,
      (limit, action) =>
        `Daily budget: ${limit === 'sans plafond' ? 'no limit' : limit}\nWhen exceeded: ${
          {
            'Alerter seulement': 'alert only',
            'Mettre toutes les banques en pause': 'pause all memory banks',
          }[action] ?? action
        }.`,
    ],
  ],
  [
    /^Appliquer le gabarit à « .* » \?$/,
    [
      /^Effet prévu : ([\s\S]*)\.$/,
      (parts) =>
        `Expected effect: ${parts
          .replace('aucun changement', 'no change')
          .replace(
            /([\d\s,.]+) modèles? mentaux? créés?|([\d\s,.]+) modèle mental créé/g,
            (m) => `${count(m.match(/[\d\s,.]+/)![0], 'mental model')} created`,
          )
          .replace(
            /([\d\s,.]+) modèles? mentaux? mis à jour|([\d\s,.]+) modèle mental mis à jour/g,
            (m) => `${count(m.match(/[\d\s,.]+/)![0], 'mental model')} updated`,
          )
          .replace(
            /([\d\s,.]+) directives? créées?/g,
            (m) => `${count(m.match(/[\d\s,.]+/)![0], 'directive')} created`,
          )
          .replace(
            /([\d\s,.]+) directives? mises? à jour/g,
            (m) => `${count(m.match(/[\d\s,.]+/)![0], 'directive')} updated`,
          )}.`,
    ],
  ],
  [
    /^Retirer l'alias « .* » \?$/,
    [
      /^Les clients qui utilisent encore « (.*) » n'atteindront plus cette banque \(et risquent d'en créer une vide\)\. Les données ne bougent pas\.$/,
      (alias) =>
        `Clients still using “${alias}” will no longer reach this memory bank and could create an empty one. Data is unchanged.`,
    ],
  ],
  [
    /^Retirer [\d\s,.]+ documents? de « .* » \?$/,
    [
      /^([\s\S]*) : ([\d\s,.]+) documents? et ([\d\s,.]+) faits? supprimés définitivement de la banque\. Les fichiers ne sont pas touchés ; les renvoyer coûtera une nouvelle extraction\.$/,
      (what, docs, facts) =>
        `${removalTarget(what)}: ${count(docs, 'document')} and ${count(facts, 'fact')} will be permanently deleted from the memory bank. Files are kept. Uploading them again will require a new extraction and its cost.`,
    ],
  ],
  [
    /^Enregistrer les étiquettes du document \?$/,
    [
      /^Ajoutées : ([\s\S]*)\nRetirées : ([\s\S]*)\n\nLes étiquettes sont propagées à tous ses faits(?: ; les observations concernées sont invalidées et reconsolidées sous les nouvelles étiquettes \(appel LLM\)|(\. Cette banque ne crée pas d'observations : rien n'est reconsolidé))\.$/,
      (added, removed, noObservations) =>
        `Added: ${added}\nRemoved: ${removed}\n\n` +
        (noObservations
          ? 'Tags are applied to all document facts. This memory bank does not create observations, so nothing is consolidated again.'
          : 'Tags are applied to all document facts. Affected observations are invalidated and consolidated again under the new tags (LLM call).'),
    ],
  ],
  [
    /^Passer la portée en « .* » \?$/,
    [
      /^Actuelle : ([\s\S]*)\. Les faits ne sont pas réextraits\. Ceux dont les observations changent de portée les perdent et repartent en consolidation \(appel LLM\), avec les faits d'autres documents qui les partageaient\. Un changement qui laisse chaque fait dans les mêmes observations ne relance rien\.$/,
      (current) =>
        `Current: ${scopeLabel(current)}. Facts are not extracted again. Facts whose observation scope changes lose their observations and are consolidated again (LLM call), along with facts from other documents that shared those observations. A change that keeps every fact in the same observations reruns nothing.`,
    ],
  ],
  [
    /^Annuler [\d\s,.]+ opérations? en attente \?$/,
    [
      /^([\d\s,.]+) opérations? en attente dans ([\d\s,.]+) banques? (?:sera annulée|seront annulées) : extractions, consolidations, régénérations\.\nC'est définitif : un document dont l'extraction est annulée devra être renvoyé depuis « Documents »\.\nUne opération déjà commencée quand vous confirmez est interrompue à sa prochaine étape ; les faits déjà extraits ne sont pas touchés\.$/,
      (n, banks) =>
        `${count(n, 'pending operation')} in ${count(banks, 'memory bank')} will be cancelled: extractions, consolidations, regenerations.\nThis is final: a document whose extraction is cancelled must be uploaded again from Documents.\nAn operation that has already started when you confirm will be interrupted at its next stage. Previously extracted facts are kept.`,
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
      /^Le document(?:, ses segments et (?:(son fait)|ses ([\d\s  .,]+) faits)| et ses segments) sont supprimés\. Irréversible : exportez d'abord si besoin\.$/,
      (one, n) =>
        `${one ? 'The document, its chunks and its fact' : n ? `The document, its chunks and its ${n.trim()} facts` : 'The document and its chunks'} will be deleted. This is irreversible: export first if needed.`,
    ],
  ],
  [
    /^Retraiter ce document \?$/,
    [
      /^(?:Son fait sera supprimé puis ré-extrait|Ses ([\d\s\u00a0\u202f.,]+) faits seront supprimés puis ré-extraits) avec la configuration actuelle du serveur \(appels LLM et VLM\)\. Les corrections manuelles faites sur ces faits seront perdues\.(?:\n\n([^\n]+))?$/,
      (n, cost) =>
        `${n ? `Its ${n} facts` : 'Its fact'} will be deleted and extracted again using the current server configuration (LLM and VLM calls). Manual corrections to these facts will be lost.${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Mettre (?:« .* »|toutes les banques) en pause \?$/,
    [
      /^(?:« (.*) »|Toutes les banques) : plus aucun envoi depuis cette app, consolidation automatique coupée\. La consolidation en cours s'arrête après son lot et les régénérations de connaissances sont annulées ; rien n'est perdu\. Les extractions déjà en file continuent\.$/,
      (bank) =>
        `${bank ? `“${bank}”` : 'All memory banks'}: no more uploads from this app, automatic consolidation turned off. The running consolidation stops after its batch and knowledge regenerations are cancelled; nothing is lost. Extractions already queued keep running.`,
    ],
  ],
  [
    /^Reprendre (?:« .* »|toutes les banques) \?$/,
    [
      /^(?:« (.*) »|Toutes les banques) : les envois reprennent, la consolidation arrêtée par la pause repart sur les faits restants et la consolidation automatique retrouve son réglage d'avant\.$/,
      (bank) =>
        `${bank ? `“${bank}”` : 'All memory banks'}: uploads resume, the consolidation stopped by the pause picks up the remaining facts and automatic consolidation returns to its setting from before.`,
    ],
  ],
  [
    /^Obtenir une réponse \?$/,
    [
      /^Le modèle rédigera une réponse à partir des faits de cette banque\.\n\n([^\n]+)\n\n([\s\S]*)$/,
      (cost, query) =>
        `The model will write an answer from the facts in this memory bank.\n\n${costSummary(cost)}\n\n${query}`,
    ],
  ],
  [
    /^Régénérer « .* » \?$/,
    [
      /^(Le modèle mental est régénéré|La page de connaissance est régénérée) par le LLM \(opération asynchrone\)\.(?:\n\n([^\n]+))?$/,
      (kind, cost) =>
        `The ${kind.startsWith('La page') ? 'knowledge page' : 'mental model'} will be regenerated by the LLM (asynchronous operation).${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    // Le nom et la question sont le texte de l'utilisateur : repris tels quels, seul le reste est traduit.
    /^(?:Modifier la question de|Renommer le modèle mental|Renommer la page de connaissance) « .* » \?$/,
    [
      /^(?:Nouveau nom : « (.*) »\n\n)?(?:Nouvelle question : ([\s\S]*)\n\n)?(?:(La page de connaissance est aussitôt régénérée|Le modèle mental est aussitôt régénéré) par le LLM pour cette question \(opération asynchrone\)\.(?:\n\n([^\n]+))?|(Son contenu ne change pas\.))$/,
      (name, query, kind, cost, unchanged) =>
        [
          name === undefined ? '' : `New name: “${name}”`,
          query === undefined ? '' : `New question: ${query}`,
          unchanged
            ? 'Its content does not change.'
            : `The ${kind.startsWith('La page') ? 'knowledge page' : 'mental model'} is regenerated right away by the LLM for this question (asynchronous operation).${cost ? '\n\n' + costSummary(cost) : ''}`,
        ]
          .filter(Boolean)
          .join('\n\n'),
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
      /^([\d\s,.]+) sources? complètes? vers « (.*) », environ ([\d\s,.]+) jetons de texte avant extraction\.\n\n([\s\S]*)\n\nLes sources modifiées remplacent leur version mémorisée\. Aucune suppression d’autres documents\. La consolidation dépend des réglages de la banque\.(\n\nCe dossier sera rattaché à « .* » : ses sources ne pourront pas être envoyées à une autre banque\.)?$/,
      (n, bank, tokens, items, binds) =>
        `${count(n, 'complete source')} to “${bank}”, approximately ${tokens.trim()} text tokens before extraction.\n\n${items}\n\nChanged sources replace their stored version. Other documents are kept. Consolidation follows the memory bank settings.${binds ? `\n\nThis folder will be linked to “${bank}”: its sources cannot be uploaded to another memory bank.` : ''}`,
    ],
  ],
  [
    /^Consolider les faits \?$/,
    [
      /^Le serveur va créer ou mettre à jour les observations à partir (?:du seul fait|des ([\d\s  .,]+) faits) pas encore consolidés?\. Cela appelle le LLM de consolidation\. Chaque fait rejoint les observations de sa portée \(celle de son document\)\.(?:\n\n([^\n]+))?$/,
      (n, cost) =>
        `The server will create or update observations from ${n ? `the ${n} facts` : 'the only fact'} not yet consolidated. This calls the consolidation LLM. Each fact joins the observations of its scope (its document’s scope).${cost ? '\n\n' + costSummary(cost) : ''}`,
    ],
  ],
  [
    /^Reconsolider les faits en échec \?$/,
    [
      /^(?:Le fait en échec de consolidation sera remis|Les ([\d\s  .,]+) faits en échec de consolidation seront remis) dans la file\. Aucune observation n'est supprimée\.$/,
      (n) =>
        `${n ? `The ${n} facts` : 'The fact'} that failed consolidation will be requeued. No observations are deleted.`,
    ],
  ],
  [
    /^Annuler ([\d\s,.]+) régénérations? en double \?$/,
    [
      /^([\d\s,.]+) connaissances? (?:est|sont) dans la file plusieurs fois : ([\d\s,.]+) régénérations? en trop (?:sera annulée|seront annulées)\.\nChaque connaissance garde une seule régénération \(celle en cours, sinon la plus récente\) : son contenu final est le même, sans payer plusieurs fois\.$/,
      (items, extra) =>
        `${count(items, 'knowledge item is', 'knowledge items are')} queued more than once: ${count(extra, 'extra regeneration')} will be cancelled.\nEach knowledge item keeps a single regeneration (the running one, otherwise the most recent): its final content is the same, without paying several times.`,
    ],
  ],
  [
    /^Annuler cette opération \?$/,
    [
      /^« ([\s\S]*) » (s'arrête après le lot en cours\. Ce qui est déjà fait est gardé ; rien n'est perdu|ne sera pas traitée)\.$/,
      (title, what) =>
        `“${operationTitle(title)}” ${what.startsWith('ne ') ? 'will not be processed' : 'stops after its current batch. What is already done is kept; nothing is lost'}.`,
    ],
  ],
  [
    /^Supprimer cette entrée \?$/,
    [
      /^L'entrée d'historique « ([\s\S]*) » sera supprimée du serveur\. Les faits déjà créés ne sont pas touchés\.$/,
      (title) =>
        `History entry “${operationTitle(title)}” will be deleted from the server. Existing facts are kept.`,
    ],
  ],
  [
    /^Relancer cette opération \?$/,
    [
      /^« ([\s\S]*) »([\s\S]*) sera remise en file\. Selon son type, cela peut consommer des appels LLM\.$/,
      (title, target) =>
        `“${operationTitle(title)}”${target} will be requeued. Depending on its type, this may use LLM calls.`,
    ],
  ],
  [
    /^Revenir aux réglages du serveur \?$/,
    [
      /^(?:Les ([\d\s,.]+) réglages propres à « (.*) » sont supprimés|Le réglage propre à « (.*) » est supprimé), y compris ceux de l'administration \(journal d'accès, etc\.\)\. Les faits existants ne changent pas\.( La consolidation automatique reste coupée jusqu'à la fin de la pause\.)?$/,
      (n, bank, oneBank, paused) =>
        `${n ? `The ${n} bank-specific settings of “${bank}” will be removed` : `The bank-specific setting of “${oneBank}” will be removed`}, including administration settings (access log, etc.). Existing facts are unchanged.${paused ? ' Automatic consolidation stays off until the pause ends.' : ''}`,
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
  if (/^(Créer|Supprimer) la directive « /.test(title)) return message;
  if (/^Modifier la directive « /.test(title)) return directiveBody(message);
  if (/^Modifier « .* » pour cette banque \?$/.test(title)) return overrideBody(message);
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
    // Libellés fixes du catalogue d’abord, puis messages d’état du moteur (service, problèmes de réglage).
    const text = (value: unknown) => {
      if (typeof value !== 'string') return value;
      const label = nativeCatalogText(value);
      return label === value ? nativeSystemMessage(value) : label;
    };
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
    if (Array.isArray(data.diagnostic))
      data.diagnostic = data.diagnostic.map((row: Row) => ({
        ...row,
        title: text(row.title),
        status: llmStatus[row.status] ?? row.status,
      }));
    data.testModelsBlocked = text(data.testModelsBlocked);
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

  for (const key of [
    'error',
    'memoryMessage',
    'actionMessage',
    'activityMessage',
    'servicesError',
    'traceError',
    'trialError',
    'diagnosticError',
    'modelError',
    'detailError',
  ])
    if (typeof data[key] === 'string') data[key] = nativeSystemMessage(data[key]);
  // Listes courtes de messages système (tableau de bord, comportement de la mémoire, dossiers suivis).
  for (const key of ['partialErrors', 'problems', 'warnings'])
    if (Array.isArray(data[key]))
      data[key] = data[key].map((item: unknown) =>
        typeof item === 'string' ? nativeSystemMessage(item) : item,
      );
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
