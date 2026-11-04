# Vérifications de Hindsight Desktop

## Moteur et contrat API

Depuis la racine :

```sh
swift test
```

XCTest vérifie le client, les ViewModels, les confirmations, les fichiers, les coûts et les
règles de service. Les tests du client comparent les requêtes à `docs/openapi.json` et décodent les
réponses minimales et complètes. Ne pas modifier les modèles générés à la main.

Après un changement du contrat : actualiser `docs/openapi.json`, lancer
`python3 scripts/generate_models.py`, puis rejouer les tests.

### Serveurs 1.2 et antérieurs

`Server120Tests` et `desktop/tests/server120.test.mjs` vérifient le passage de `rerank`
dans recall (hériter de la banque, activer, désactiver), son omission en 1.1, les réglages de
banque après confirmation et les statistiques `split_by=model`. Les services spécialisés
sont valorisés au tarif hébergé indicatif : ces statistiques ne donnent pas le fournisseur
ni son URL, et ne prouvent donc pas qu'un appel a été facturé. Les appels locaux n'ont pas
de coût par jeton. Un changement de serveur vide le relevé ; un échec reste visible et
réessayable ; changer la grille tarifaire recalcule aussi le cache.

`cd desktop && npm run test:models` vérifie les contrôles de recherche, les interrupteurs
par banque, la valorisation indicative et la carte Modèles Hindsight avec des données
fictives, à deux largeurs de fenêtre.

Le catalogue des réglages documente `hindsight` pour la décision, le reranker et les
embeddings. Les clés dédiées peuvent rester vides après `hindsight-admin cloud login`.
Dans Recherche → Filtres, les choix prune/dedup restent propres à la requête ; les défauts
persistants se trouvent dans Structure de la mémoire → Recherche. Le serveur doit avoir
un modèle de décision configuré pour recall. Changer d'embeddings exige une ré-indexation ;
changer de reranker n'en exige pas.

## Pont natif et interface

Depuis `desktop/` :

```sh
npm run bridge:build
npm test
npm run build
```

Les tests du pont emploient un faux serveur HTTP, des réglages en mémoire et un dossier temporaire.
Ils vérifient l’absence d’écriture lors des lectures, la confirmation de reflect, le rejet d’un
rejeu, le texte requis pour une suppression, l’invalidation lors d’un changement de banque,
le confinement des chemins et liens symboliques, les URL et les commandes autorisées.

## Test de rendu en navigateur

```sh
cd desktop
npx playwright install chromium
npm run test:ui
```

Ce test utilise uniquement des données fictives. Il parcourt les vues, ouvre des documents et
synthèses, recherche des faits, filtre les sources, inspecte le graphe, utilise les raccourcis et
vérifie les deux thèmes. Les captures sont enregistrées dans `desktop/screenshots/`.
Ce test ne prouve pas les dialogues et permissions du bundle Tauri : vérifier ceux-ci dans l’app.

## Construire et vérifier Tauri

```sh
cd desktop
npm run tauri:build -- --bundles app
```

Ouvrir `desktop/src-tauri/target/release/bundle/macos/Hindsight Desktop.app`.

1. Vérifier que le catalogue local se charge sans le serveur, puis que la connexion charge les banques.
2. Consulter une source et sa provenance, filtrer par projet et famille, puis vérifier les statuts des collecteurs.
3. Lire une synthèse et un document avec pièces jointes ; vérifier l’historique et le surlignage dans le texte.
4. Vérifier recall et texte ; pour reflect, inspecter l’estimation et la confirmation puis annuler.
5. Préparer une écriture, un retraitement ou une suppression : inspecter les détails et le texte requis, puis annuler.
6. Vérifier les quotas, leur date de relevé et la distinction entre frais à l’usage et jetons d’abonnement.
7. Vérifier la sélection d’un dossier et le dialogue d’enregistrement d’un export dans un emplacement de test.
8. Inspecter les modèles, le diff et les sauvegardes sans enregistrer ni redémarrer le serveur.
9. Vérifier l’absence de secrets dans les champs affichés, les diff et les journaux.
10. Vérifier les thèmes, le clavier, la navigation rapide, les fenêtres et la taille minimale de la fenêtre.

La collecte, l’extraction, la consolidation, les suppressions réelles, les connexions OAuth et les
opérations du service exigent une autorisation explicite. Les tests de lecture n’en déclenchent pas.

## Migration de l’ancien frontend

Les cibles `HindsightUI` et `HindsightMac`, les stubs SwiftUI et les anciens scripts d’installation
ne font plus partie du dépôt. NOMAD Studio importe encore l’ancien module dans sa propre copie :
son intégration devra être adaptée avant une mise à jour de cette dépendance.

## Mises à jour intégrées

Les tests `AppUpdateTests` vérifient la reconstruction Tauri dans une destination séparée, la validation de l’identifiant du bundle, le remplacement, le refus des modifications locales et des changements de dépôt après confirmation. Dans l’app, vérifier Réglages → Mises à jour sans confirmer une installation réelle : le journal et les états restent actualisés indépendamment de la connexion au serveur Hindsight.

## Atlas interactif

`cd desktop && npm run test:graph` vérifie groupes, sélection stable, voisinage à deux degrés, recherche sans accents, chemin entre deux idées, inspection d’une étape sans perdre le parcours, rupture de chemin par un filtre, provenance, pan/zoom, clavier, thèmes et absence de débordement à trois largeurs. Le navigateur est isolé et les données entièrement fictives. Un Chromium Playwright installé est utilisé par défaut ; sur macOS, Chrome déjà installé peut servir au test, et `HINDSIGHT_BROWSER_EXECUTABLE` permet de choisir un exécutable.

Les tests du modèle de graphe vérifient la topologie, les doublons, les nœuds isolés, les filtres, la détermination des groupes et le placement de 1 000 nœuds. Le test de pont vérifie les totaux serveur, la conservation du mode et l’accès à la source d’un fait. `swift test --filter GraphTests` couvre le chargement des données sans simulation native inutile.

Le test visuel de l’atlas inclut aussi une carte synthétique dense de 100 nœuds : agrégation par groupes, nombre exact de liaisons, accès à la liste des membres au clic et déploiement au zoom.
