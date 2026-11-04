# Publier une bêta macOS

Destination publique : `paabL/hindsight-desktop`. Publier un export vérifié des
sources, avec un nouvel historique ; conserver le dépôt de développement privé.
Ne pas inclure `.git`, `.claude`, données personnelles, captures réelles, dossiers
de compilation, `node_modules`, outils locaux ou secrets.

1. Vérifier les tests Swift, le pont, les tests frontend, le rendu et le build
   TypeScript. Ouvrir le bundle sur un profil de test sans réglages personnels.
2. Régénérer les notices après tout changement de dépendances ; inclure LICENSE,
   NOTICE, confidentialité et les crédits complets dans la distribution.
3. Construire pour l'architecture annoncée. Le pont Swift inclus doit avoir la
   même architecture que l'app. Ne pas annoncer Intel sans bundle testé Intel.
4. Sans compte Apple Developer : annoncer clairement **bêta non notariée**.
   Une signature ad hoc ne vérifie pas l'identité de l'éditeur. Expliquer
   l'autorisation ponctuelle dans Réglages Système ; ne jamais demander de
   désactiver Gatekeeper ni de supprimer globalement la quarantaine.
5. Joindre le DMG et son empreinte SHA-256 à une release GitHub marquée
   prerelease. Indiquer version, macOS minimum, architecture, serveur nécessaire,
   contrôles réellement passés et limites connues.
6. Activer les signalements privés de vulnérabilités du dépôt public, vérifier
   les liens de téléchargement puis contacter l'équipe upstream avec le
   [message préparé](UPSTREAM.md). Aucune affiliation ne doit être suggérée.

Une distribution vérifiée par Apple peut être ajoutée plus tard : Developer ID
Application, signature du pont et de l'app, notarisation puis agrafage du ticket.
Références : [Tauri macOS signing](https://v2.tauri.app/distribute/sign/macos/),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Apple — ouvrir une app](https://support.apple.com/102445).

Pour construire le DMG gratuit après avoir figé les sources publiques :

```sh
cd desktop
HINDSIGHT_RELEASE_COMMIT=<commit-public-complet> node scripts/package-release.mjs
```

Le paquet, son empreinte et son manifeste sont créés dans `desktop/release/`.
Le script ne publie rien et n'installe pas l'app.
