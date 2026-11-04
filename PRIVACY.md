# Confidentialité / Privacy

Dernière mise à jour / Last updated: 2026-11-04.

## Français

Hindsight Desktop est un client communautaire indépendant. L'app n'ajoute
ni publicité, ni mesure d'audience, ni service de collecte de l'éditeur.
Elle communique avec le serveur Hindsight que vous configurez. Elle n'est
pas un service d'hébergement de vos souvenirs.

- **Fichiers locaux.** Le dossier mémoire choisi contient vos sources,
  catalogues et états d'envoi. Les collecteurs configurés peuvent lire vos
  conversations, dépôts et documents. Vérifiez l'aperçu avant d'envoyer.
- **Envois.** Les documents, requêtes et recherches nécessaires sont envoyés
  à votre serveur. Celui-ci peut appeler les fournisseurs de modèles prévus
  par sa configuration, avec leurs coûts et conditions de conservation.
  Une connexion locale ne garantit donc pas un traitement entièrement local.
- **Stockage de l'app.** Les réglages sont conservés dans les préférences macOS
  `local.hindsight.desktop`. L'historique local sous
  `~/Library/Application Support/HindsightDesktop/usage-ledger.json` conserve
  compteurs, fournisseur, modèle, horodatage et identifiants de banque/document,
  sans texte des prompts ou réponses. Les états et sauvegardes du dossier
  mémoire peuvent contenir vos documents.
- **Comptes.** Les connexions sont déléguées aux clients officiels installés.
  Hindsight Cloud conserve sa clé dans `~/.hindsight/cloud/credentials.json`.
  La déconnexion locale ne révoque pas une clé dans le cloud.
- **Quotas d'abonnement.** Vérifiés uniquement sur demande confirmée dans
  Consommation, ils utilisent les identifiants déjà
  enregistrés par Codex et, si autorisé, Claude Code, uniquement auprès de leurs
  propres services. Ces interfaces de quota peuvent changer. Aucun document
  ou prompt n'est nécessaire pour cette vérification.
- **Mises à jour.** Une recherche de mise à jour depuis les sources contacte
  le dépôt Git configuré. Les téléchargements de l'app et signalements GitHub
  relèvent aussi des conditions de GitHub.

Supprimer l'app ne supprime ni le serveur, ni ses banques, ni le dossier
mémoire ou les comptes officiels. Pour effacer des souvenirs côté serveur,
utilisez les suppressions confirmées puis vérifiez la politique de sauvegarde
de votre hébergeur. Ne joignez pas de conversation, jeton ou journal complet
à un signalement public. Voir [Sécurité](SECURITY.md).

## English

Hindsight Desktop is an independent community client. The app adds no ads,
analytics, or publisher-operated collection service. It connects to the
Hindsight server you configure and does not host your memories.

Your selected memory folder contains source files, catalogs and upload state.
Configured collectors may read conversations, repositories and documents.
Review the preview before sending. The server receives the documents and
queries needed for your requested actions, and may send them to its configured
model providers. Their fees and retention policies apply: a local server does
not necessarily mean local model processing.

macOS preferences are stored under `local.hindsight.desktop`. The local ledger
at `~/Library/Application Support/HindsightDesktop/usage-ledger.json` stores
counts, provider/model names, timestamps and bank/document identifiers, without
prompt or response text. Files and backups in the memory folder may contain
your document content.

Sign-in uses separately installed official clients. Hindsight Cloud stores its
key in `~/.hindsight/cloud/credentials.json`; local sign-out does not revoke the
cloud key. Subscription quota checks use existing Codex credentials and,
when allowed, Claude Code credentials, only with their own services, after
an explicit confirmed check in Usage. There is no automatic account access. These
quota interfaces may change; no document or prompt is needed for the check.
Source update checks contact your configured Git repository. GitHub downloads
and issue reports are also subject to GitHub's terms.

Removing the app leaves your server, banks, memory folder and official accounts
in place. Use confirmed server deletions and check your host's backup policy
to erase server memories. Never post conversations, credentials or complete
logs in a public report. See [Security](SECURITY.md).
