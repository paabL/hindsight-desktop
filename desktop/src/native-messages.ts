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
  Régénérer: 'Regenerate',
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
  'Import terminé.': 'Import complete.',
  'Modèle appliqué.': 'Template applied.',
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
  'Configuration réinitialisée.': 'Settings reset.',
  'Directive créée.': 'Directive created.',
  'Directive mise à jour.': 'Directive updated.',
  'Directive supprimée.': 'Directive deleted.',
  'Page de connaissance supprimée.': 'Knowledge page deleted.',
  'Le service est déjà en cours de modification.': 'The service is already being changed.',
  'Ce document n’est plus ouvert.': 'This document is no longer open.',
  'Test des modèles terminé. Consultez le résultat dans Serveur & modèles.':
    'Model test complete. See the result in Server & models.',
  "Filtre d'opérations inconnu.": 'Unknown operations filter.',
  'Le test des LLM est désactivé sur ce serveur. La relance des opérations reste disponible. Pour activer ce diagnostic, ajoutez HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true au script de lancement, puis redémarrez le serveur.':
    'LLM testing is disabled on this server. Retrying operations is still available. To enable this check, add HINDSIGHT_API_ENABLE_BANK_LLM_HEALTH=true to the launch script, then restart the server.',
  "Pause en cours sur toutes les banques : rien n'est envoyé. Reprenez depuis « Consommation ».":
    'All memory banks are paused: nothing is sent. Resume from Activity › Usage.',
  'Toutes les banques sont en pause.': 'All memory banks are paused.',
  "Le serveur n'est pas lancé par le service de l'app : ajoutez HINDSIGHT_API_WORKER_ENABLED=false à son environnement et redémarrez-le, ou mettez les banques en pause.":
    'The server is not started by the app’s service: add HINDSIGHT_API_WORKER_ENABLED=false to its environment and restart it, or pause the memory banks.',
  'Une autre action est en cours (gel, vidage) : réessayez dans un instant.':
    'Another action is in progress (freeze or clear): try again in a moment.',
  'File gelée au prochain démarrage du serveur.':
    'The queue will be frozen when the server next starts.',
  'File reprise au prochain démarrage du serveur.':
    'The queue will resume when the server next starts.',
  'Le serveur a redémarré mais son worker tourne toujours : votre script fixe probablement HINDSIGHT_API_WORKER_ENABLED.':
    'The server restarted but its worker is still running: your script probably sets HINDSIGHT_API_WORKER_ENABLED.',
  "File gelée : le serveur répond mais ne traite plus d'opérations.":
    'Queue frozen: the server responds but no longer processes operations.',
  'File reprise : le serveur traite à nouveau ses opérations.':
    'Queue resumed: the server processes operations again.',
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
  "Le serveur n'est pas lancé par le service de l'app : sa file ne peut pas être gelée d'ici.":
    'The server is not started by the app’s service: its queue cannot be frozen from here.',
  "Le script de lancement a changé depuis votre dernière approbation : redémarrez d'abord le serveur depuis « Serveur & modèles ».":
    'The launch script changed since your last approval. Restart the server from Server & models first.',
  'Démarrage annulé.': 'Start cancelled.',
  'Tags mis à jour.': 'Tags updated.',
  'Portée mise à jour.': 'Scope updated.',
  "Journal d'audit activé pour cette banque.": 'Audit log enabled for this memory bank.',
  "Journal d'audit désactivé.": 'Audit log disabled.',
  "Texte reconstitué à partir des chunks (le texte original n'est pas stocké sur le serveur).":
    'Text rebuilt from chunks (the original text is not stored on the server).',
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
  'Choisissez un dossier mémoire et une banque.': 'Choose a memory folder and a memory bank.',
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
  'Source hors du dossier commun.': 'Source outside the shared folder.',
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
  'La sélection ou la politique a changé ; rechargez la vue.':
    'The selection or policy changed. Reload the view.',
  'La politique a changé ; rechargez la vue.': 'The policy changed. Reload the view.',
  'La version mémorisée a changé ; rechargez la vue.':
    'The stored version changed. Reload the view.',
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
  `${n} ${n.replace(/\D/g, '') === '1' ? singular : plural}`;
const toRestore = (banks?: string) => (banks ? ` To restore as soon as possible: ${banks}.` : '');
const dashboardParts: Record<string, string> = {
  version: 'version',
  entités: 'entities',
  'série temporelle': 'time series',
  documents: 'documents',
  tags: 'tags',
  échecs: 'failures',
  configuration: 'settings',
};
const serverActions: Record<string, string> = {
  démarré: 'Server started',
  redémarré: 'Server restarted',
  'redémarré, file gelée': 'Server restarted, queue frozen',
  'redémarré, file reprise': 'Server restarted, queue resumed',
};

// Messages d’état composés par le moteur. Les noms, identifiants, chemins et erreurs du serveur
// capturés sont réinsérés tels quels. Avant les règles générales (« Échec : … »).
const engineRules: Rule[] = [
  [
    /^Impossible de lister les banques : ([\s\S]*)$/,
    (detail) => `Unable to list memory banks: ${detail}`,
  ],
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
    /^Fusion terminée( \([^)]*\))?(?: ; « (.*?) » (?:mène désormais à « (.*?) »|supprimée))?\. Lancez la consolidation de « (.*) » pour intégrer les nouveaux faits aux observations\.$/,
    (counts, source, aliasTarget, target) =>
      `Merge complete${counts || ''}${source ? (aliasTarget ? `; “${source}” now leads to “${aliasTarget}”` : `; “${source}” deleted`) : ''}. Run consolidation on “${target}” to add the new facts to its observations.`,
  ],
  [
    /^Fusion terminée( \([^)]*\))?\. « (.*) » est CONSERVÉE : ([\d\s,.]+) document\(s\) ignoré\(s\) n'existent que dans la source\. Vérifiez, puis supprimez-la depuis « Réglages › Banque »\.$/,
    (counts, source, n) =>
      `Merge complete${counts || ''}. “${source}” was KEPT: ${count(n, 'skipped document')} ${n.replace(/\D/g, '') === '1' ? 'exists' : 'exist'} only in the source. Check, then delete it from Settings › Memory bank.`,
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
  [
    /^Modèle mental créé ; génération lancée \((.*)\)\.$/,
    (id) => `Mental model created; generation started (${id}).`,
  ],
  [/^Régénération lancée \((.*)\)\.$/, (id) => `Regeneration started (${id}).`],
  [/^Archive prête \((.*)\)\.$/, (size) => `Archive ready (${size}).`],
  [/^Échec de l'export : ([\s\S]*)$/, (detail) => `Export failed: ${detail}`],
  [/^Échec du clonage : ([\s\S]*)$/, (detail) => `Clone failed: ${detail}`],
  [/^Échec de l'import : ([\s\S]*)$/, (detail) => `Import failed: ${detail}`],
  [/^Fichier de modèle invalide : ([\s\S]*)$/, (detail) => `Invalid template file: ${detail}`],
  [/^Échec de la validation : ([\s\S]*)$/, (detail) => `Validation failed: ${detail}`],
  [/^([\d\s,.]+) observation\(s\) effacée\(s\)\.$/, (n) => `${count(n, 'observation')} cleared.`],
  [/^([\d\s,.]+) observation\(s\) supprimée\(s\)\.$/, (n) => `${count(n, 'observation')} deleted.`],
  [/^([\d\s,.]+) fait\(s\) supprimé\(s\)\.$/, (n) => `${count(n, 'fact')} deleted.`],
  [
    /^L'opération (.*) n'est pas terminée ; suivez-la dans « Activité › Traitements »\.$/,
    (id) => `Operation ${id} is not finished yet. Follow it in Activity › Processing.`,
  ],
  [
    /^La banque « (.*) » est en pause : rien n'y est envoyé\. Reprenez-la pour continuer\.$/,
    (bank) => `Memory bank “${bank}” is paused: nothing is sent to it. Resume it to continue.`,
  ],
  [
    /^(?:« (.*?) » est en pause|Toutes les banques sont en pause)\.( Rien n'est envoyé ; la consolidation automatique et les régénérations de connaissances seront coupées dès que le serveur répondra\.)?(?: ([\d\s,.]+) régénérations? de connaissances? annulées?\.)?(?: Consolidation automatique pas encore coupée pour (.*) \(nouvel essai à la reconnexion\)\.)?$/,
    (bank, nothing, cancelled, failures) =>
      (bank ? `“${bank}” is paused.` : 'All memory banks are paused.') +
      (nothing
        ? ' Nothing is sent. Automatic consolidation and knowledge regenerations will be turned off as soon as the server responds.'
        : '') +
      (cancelled ? ` ${count(cancelled, 'knowledge regeneration')} cancelled.` : '') +
      (failures
        ? ` Automatic consolidation is not turned off yet for ${failures} (it will be retried on reconnect).`
        : ''),
  ],
  [/^Impossible de lister la file : ([\s\S]*)$/, (detail) => `Unable to list the queue: ${detail}`],
  [
    /^Aucune régénération de connaissance en double(?: dans « (.*) »)?\.$/,
    (bank) => `No duplicate knowledge regenerations${bank ? ` in “${bank}”` : ''}.`,
  ],
  [
    /^« (.*?) » n'est plus en pause à part, mais la pause de toutes les banques s'applique encore\.(?: À rétablir dès que possible : (.*)\.)?$/,
    (bank, restore) =>
      `“${bank}” is no longer paused on its own, but the pause on all memory banks still applies.${toRestore(restore)}`,
  ],
  [
    /^« (.*?) » reprend : sa consolidation automatique retrouve son réglage d'avant la pause\.(?: À rétablir dès que possible : (.*)\.)?$/,
    (bank, restore) =>
      `“${bank}” resumes: automatic consolidation returns to its setting from before the pause.${toRestore(restore)}`,
  ],
  [
    /^Toutes les banques reprennent : la consolidation automatique retrouve son réglage d'avant la pause\.(?: Restent en pause : (.*?)\.)?(?: À rétablir dès que possible : (.*)\.)?$/,
    (paused, restore) =>
      `All memory banks resume: automatic consolidation returns to its setting from before the pause.${paused ? ` Still paused: ${paused}.` : ''}${toRestore(restore)}`,
  ],
  [
    /^Toutes les banques reprennent\.(?: À rétablir dès que possible : (.*)\.)?$/,
    (restore) => `All memory banks resume.${toRestore(restore)}`,
  ],
  [
    /^Aucune opération en attente dans « (.*) »\.$/,
    (bank) => `No pending operations in “${bank}”.`,
  ],
  [
    /^([\d\s,.]+) opérations? annulées?(?:\.|, ([\d\s,.]+) non annulée\(s\) : ([\s\S]*))$/,
    (n, failed, detail) =>
      `${count(n, 'operation')} cancelled${failed ? `, ${failed} not cancelled: ${detail}` : '.'}`,
  ],
  [/^Le test des LLM n'a pas abouti : ([\s\S]*)$/, (detail) => `The LLM test failed: ${detail}`],
  [
    /^Décision (recall|reflect|consolidation) : l'URL Cloud hériterait de la clé du modèle local\. Choisissez l'URL locale ou une clé propre à cette opération avant d'enregistrer\.$/,
    (operation) =>
      `Decision model for ${operation}: the Cloud URL would inherit the local model’s key. Choose the local URL or a key specific to this operation before saving.`,
  ],
  [
    /^Décision (recall|reflect|consolidation) sur Hindsight Cloud : connectez le compte ou configurez (\S+)\. Pour un modèle local, choisissez l'URL de ce Mac\.$/,
    (operation, key) =>
      `Decision model for ${operation} on Hindsight Cloud: connect the account or configure ${key}. For a local model, choose this Mac’s URL.`,
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
    /^Serveur (démarré|redémarré|redémarré, file gelée|redémarré, file reprise) : l'API répond\.$/,
    (action) => `${serverActions[action]}: the API is responding.`,
  ],
  [
    /^Structure enregistrée \(([\d\s,.]+) réglage\(s\)\)\.$/,
    (n) => `Memory structure saved (${count(n, 'setting')}).`,
  ],
  [
    /^Impossible de préparer la relance : ([\s\S]*)$/,
    (detail) => `Unable to prepare the retry: ${detail}`,
  ],
  [
    /^Relance interrompue : ([\d\s,.]+) opération\(s\) remise\(s\) en file\.$/,
    (n) => `Retry interrupted: ${count(n, 'operation')} requeued.`,
  ],
  [
    /^Retraitement lancé \(opération (.*)\)\. Suivez-le dans « Activité › Traitements »\.$/,
    (id) => `Reprocessing started (operation ${id}). Follow it in Activity › Processing.`,
  ],
  [/^Supprimé \(([\d\s,.]+) fait\(s\)\)\.$/, (n) => `Deleted (${count(n, 'fact')}).`],
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
    /^([\d\s,.]+) document\(s\) ajouté\(s\) ou mis à jour, ([\d\s,.]+) déjà à jour\. Aucun traitement Hindsight\.$/,
    (added, unchanged) =>
      `${count(added, 'document')} added or updated, ${unchanged} already up to date. Nothing was processed by Hindsight.`,
  ],
  [/^Collecte impossible : ([\s\S]*)$/, (detail) => `Collection failed: ${detail}`],
  [/^Serveur redémarré, mais : ([\s\S]*)$/, (detail) => `Server restarted, but: ${detail}`],
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
    /^([\d\s,.]+) sources envoyées ; traitement à suivre dans cette liste\.$/,
    (n) => `${count(n, 'source')} uploaded. Follow processing in this list.`,
  ],
  [/^Relecture impossible : ([\s\S]*)$/, (detail) => `Reload failed: ${detail}`],
  [
    /^Aucun fichier lisible parmi la sélection : ([\s\S]*)$/,
    (files) => `No readable files in the selection: ${files}`,
  ],
  [/^Vérification impossible : ([\s\S]*)$/, (detail) => `Check failed: ${detail}`],
  [
    /^(\d+)\/(\d+) document\(s\) retiré\(s\) de « (.*?) »\.(?: Échecs : ([\s\S]*))?$/,
    (removed, total, bank, failures) =>
      `${removed}/${total} document(s) removed from “${bank}”.${failures ? ` Failures: ${failures}` : ''}`,
  ],
  [
    /^(\d+)\/(\d+) fichier\(s\) mis en file d'extraction dans « (.*?) » \((\d+) opération\(s\)\)\.(?: Refusés : ([\s\S]*))?$/,
    (sent, total, bank, operations, rejected) =>
      `${sent}/${total} file(s) queued for extraction in “${bank}” (${operations} operation(s)).${rejected ? ` Rejected: ${rejected}` : ''}`,
  ],
  [
    /^(version|entités|série temporelle|documents|tags|échecs|configuration) : ([\s\S]*)$/,
    (part, detail) => `${dashboardParts[part]}: ${detail}`,
  ],
];

const rules: Rule[] = [
  [
    /^Hindsight Cloud : connectez votre compte ou configurez (.*)\. Pour un modèle local, choisissez « Sur ce Mac »\.$/,
    (key) =>
      `Hindsight Cloud: connect your account or configure ${key}. For a local model, choose “On this Mac”.`,
  ],
  [/^Démarrage impossible : ([\s\S]*)$/, (detail) => `Startup failed: ${detail}`],
  [
    /^Ce dossier est rattaché à la banque « (.*) »\. Sélectionnez-la pour envoyer ou retirer ses sources\.$/,
    (bank) =>
      `This folder belongs to the “${bank}” memory bank. Select it to upload or remove its sources.`,
  ],
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
  [/^Créer le modèle mental « (.*) » \?$/, (name) => `Create mental model “${name}”?`],
  [/^Régénérer « (.*) » \?$/, (name) => `Regenerate “${name}”?`],
  [/^Supprimer le modèle mental « (.*) » \?$/, (name) => `Delete mental model “${name}”?`],
  [/^Supprimer la page de connaissance « (.*) » \?$/, (name) => `Delete knowledge page “${name}”?`],
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
    /^Annuler ([\d\s]+) régénérations? en double \?$/,
    (n) => `Cancel ${n} duplicate regeneration(s)?`,
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
  'Source à relier au catalogue': 'Not linked to the catalog yet',
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
  'Les faits sont conservés ; les observations seront recréées par une nouvelle consolidation (appels LLM).':
    'Facts are kept. Observations will be recreated through a new consolidation (LLM calls).',
  "Irréversible. Les documents restent, mais leurs faits disparaissent. Exportez la banque d'abord.":
    'Irreversible. Documents remain, but their facts are deleted. Export the memory bank first.',
  "Faits, documents, entités, observations, configuration : tout est supprimé, sans retour possible. Exportez-la d'abord.":
    'Facts, documents, entities, observations and settings will all be permanently deleted. Export the memory bank first.',
  "La banque revient aux valeurs globales du serveur (missions, disposition, réglages d'extraction et de recherche…).":
    'The memory bank returns to the server’s global settings (missions, disposition, extraction and search settings…).',
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
    /^Régénérer « .* » \?$/,
    [
      /^(Le modèle mental est régénéré|La page de connaissance est régénérée) par le LLM \(opération asynchrone\)\.(?:\n\n([^\n]+))?$/,
      (kind, cost) =>
        `The ${kind.startsWith('La page') ? 'knowledge page' : 'mental model'} will be regenerated by the LLM (asynchronous operation).${cost ? '\n\n' + costSummary(cost) : ''}`,
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
      /^(\d+) sources complètes vers « (.*) », environ (\d+) jetons de texte avant extraction\.\n\n([\s\S]*)\n\nLes sources modifiées remplacent leur version mémorisée\. Aucune suppression d’autres documents\. La consolidation dépend des réglages de la banque\.(\n\nCe dossier sera rattaché à « .* » : ses sources ne pourront pas être envoyées à une autre banque\.)?$/,
      (n, bank, tokens, items, binds) =>
        `${n} complete sources to “${bank}”, approximately ${tokens} text tokens before extraction.\n\n${items}\n\nChanged sources replace their stored version. Other documents are kept. Consolidation follows the memory bank settings.${binds ? `\n\nThis folder will be linked to “${bank}”: its sources cannot be uploaded to another memory bank.` : ''}`,
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
    /^Annuler ([\d\s]+) régénérations? en double \?$/,
    [
      /^([\d\s]+) connaissances? (?:est|sont) dans la file plusieurs fois : ([\d\s]+) régénérations? en trop (?:sera annulée|seront annulées)\.\nChaque connaissance garde une seule régénération \(celle en cours, sinon la plus récente\) : son contenu final est le même, sans payer plusieurs fois\.$/,
      (items, extra) =>
        `${count(items, 'knowledge item is', 'knowledge items are')} queued more than once: ${count(extra, 'extra regeneration')} will be cancelled.\nEach knowledge item keeps a single regeneration (the running one, otherwise the most recent): its final content is the same, without paying several times.`,
    ],
  ],
  [
    /^Annuler cette opération \?$/,
    [
      /^« ([\s\S]*) » sera interrompue si elle est en attente ou en cours\.$/,
      (title) => `“${operationTitle(title)}” will be interrupted if it is pending or running.`,
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
