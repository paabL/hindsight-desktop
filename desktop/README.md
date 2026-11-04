# Hindsight Desktop — guide technique

Pour installer la bêta et les premiers pas, lire le [guide public](../README.md).
Client communautaire indépendant, sans affiliation officielle avec Vectorize AI, Inc.
Voir [licence](../LICENSE), [confidentialité](../PRIVACY.md) et [crédits](../THIRD_PARTY_NOTICES.md).

Application **Tauri 2 + React / TypeScript** sur macOS 15 et plus, unique frontend du dépôt. L’interface est entièrement en React. Le moteur existant `HindsightCore` reste réutilisé en interne via un pont Swift ; la coque Tauri contient uniquement la liaison Rust nécessaire à l’application.

La direction visuelle privilégie le graphite, le blanc et les gris froids : navigation stable, tableaux lisibles, hiérarchie sobre, thèmes sombre et clair. La vue Mémoire est l’accueil ; les outils spécialisés restent dans Avancé.

## Démarrer

Node.js 22.18 ou plus récent, Xcode 16+, Swift 6 et Rust stable sont nécessaires pour le développement. Les commandes se lancent dans ce dossier.

```sh
npm ci
npm run dev
```

Le script utilise le Rust système, ou le Rust isolé dans `.toolchain/` s’il existe. Aucun changement du PATH utilisateur n’est nécessaire. Le moteur Swift est compilé automatiquement.

## Construire l’application

```sh
npm run tauri:build -- --bundles app
```

Le bundle se trouve dans `src-tauri/target/release/bundle/macos/Hindsight Desktop.app`. Il est construit localement et n’est pas installé automatiquement. Son identifiant est `local.hindsight.desktop.tauri`. Le pont natif est inclus : Node et Rust ne sont pas nécessaires pour ouvrir l’application construite.

`npm run web:dev` ouvre seulement l’interface dans un navigateur. Le bouton « Explorer un exemple » donne accès à des données fictives, explicitement signalées. L’accès aux fichiers et au serveur passe par Tauri.

## Fonctions

| Vue             | Contenu                                                                                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mémoire         | Sources locales et documents Hindsight, état réel des versions, inclusion par source ou filtre, collecte et aperçu avant envoi                                    |
| Synthèses       | Liste, contenu, création, actualisation et suppression confirmées                                                                                         |
| Recherche       | Recall, texte, reflect confirmé ; filtres par tags, type, entité, tâche et période ; faits et document d’origine                                          |
| Lecteur de documents (Avancé) | Texte mémorisé, faits, historique, pièces jointes, tags, portées, retraitement et suppression |
| Dossiers suivis | Couverture, sélection et envoi, retrait, suivi des fichiers texte et activation confirmée de la synchronisation automatique                               |
| Consommation    | Traces, rythme, coûts, quotas Codex et Claude, graphiques, tarifs, plafonds quotidiens et d’abonnement, pause / gel / vidage                              |
| Vue d’ensemble  | Statistiques, types de faits, file et derniers documents                                                                                                  |
| Chronologie     | Événement ou mention, recherche, documents d’origine, jusqu’à 20 000 faits                                                                                |
| Graphe          | Atlas par groupes, passerelles, voisinage à deux degrés, parcours entre idées, filtres de liens et faits avec leurs sources                                                                         |
| Activité        | Lectures, traces des modèles et journal d’accès                                                                                                           |
| Structure       | Missions, extraction, consolidation, recherche, disposition, réglages avancés, essai à blanc                                                              |
| Serveur         | Service launchd, modèles par rôle, comptes OAuth via clients officiels, diff, sauvegardes et journal                                                      |
| Administration  | Banques, directives, export, clone, fusion, import ZIP / JSON, aperçu de synchronisation du projet, surcharges et suppressions                            |
| Hermes          | Sessions, aperçu, préparation et import confirmé                                                                                                          |

Les changements de configuration de banque utilisent l’API du serveur. Les modèles sont toujours réglés dans le script de lancement, via le moteur existant. Les fonctions dépendent des capacités annoncées par le serveur et des outils locaux configurés.

Dans **Réglages → Mises à jour de l’application**, recherchez les commits disponibles puis confirmez leur installation. La copie locale est reconstruite dans `.update-target/`, puis le bundle est remplacé avec restauration de l’ancienne version si l’échange échoue. Un bouton propose ensuite la relance. Une copie modifiée bloque les commits distants ; **Recompiler cette copie** permet de reconstruire les modifications locales après confirmation. Node.js, Xcode et Rust restent nécessaires. La barre des menus n’est pas intégrée ; les quotas restent dans Consommation.

## Architecture et protections

```text
src/                       Interface React / TypeScript
src-tauri/                 Coque Tauri, commande privée et dialogues de fichiers
../Sources/HindsightBridge Projections de données et commandes vers HindsightCore
../Sources/HindsightCore   Logique existante, API, fichiers, coûts et confirmations
```

Le pont est un processus enfant privé, connecté par son entrée et sa sortie standard. Il n’ouvre aucun serveur HTTP supplémentaire. Les commandes sont déclarées explicitement ; le renderer n’a ni accès Node, ni accès direct au système de fichiers, ni commande shell générique. Tauri utilise une politique de contenu restrictive. Les documents sont rendus sans HTML brut.

Les écritures, suppressions, générations et opérations de service passent par les `ConfirmationRequest` du moteur. Le pont exige l’identifiant de confirmation actif et le texte requis, puis consomme la confirmation avant l’action. Changer de banque ou de serveur invalide les demandes en attente. Les pièces jointes sont limitées aux pièces du document ouvert ; les lectures locales sont confinées au dossier `collection/`, après résolution des liens symboliques.

Les préférences utilisent `local.hindsight.desktop`, dans un domaine dédié. L’historique des compteurs de consommation est conservé dans `~/Library/Application Support/HindsightDesktop/usage-ledger.json`, sans prompts ni réponses. La collecte ne lance pas l’extraction ou la consolidation. Aucun traitement mémoire ne démarre automatiquement au premier lancement. Le suivi des compteurs peut fonctionner en arrière-plan tant que l’application est ouverte ; une action automatique sur plafond exige l’autorisation explicite dans les réglages de plafonds.

## Vérifier

```sh
npm run bridge:build
npm test
npm run build
npx playwright install chromium  # une fois, pour le test de rendu en navigateur
npm run test:ui
```

Les tests du pont utilisent un faux serveur HTTP et des réglages en mémoire. Ils vérifient notamment l’absence d’écriture lors des lectures, la confirmation de reflect, les confirmations non rejouables, le texte de suppression, le confinement des fichiers et la validation des URL. Le test de rendu en navigateur fonctionne sans accès natif. Ses captures utilisent uniquement l’exemple fictif et sont enregistrées dans `screenshots/`.

La suite Swift d’origine reste disponible avec `swift test` à la racine du dépôt. Les opérations réelles de collecte, consolidation, suppression, connexion OAuth et contrôle du service ne sont pas exécutées par le test visuel.

## Mettre à jour depuis l’app

Ouvrir **Réglages → Mises à jour de l’application**, rechercher les commits disponibles puis confirmer leur installation. L’app reconstruit la version dans `desktop/.update-target/`, valide le bundle, remplace l’app ouverte et propose de la relancer. Node.js, Xcode et Rust sont nécessaires. La copie locale doit être propre pour appliquer des commits distants ; **Recompiler cette copie** permet de reconstruire les modifications locales après confirmation. Le remplacement restaure l’ancien bundle si l’échange échoue.

Au premier lancement, le dossier mémoire est choisi explicitement, sans parcourir automatiquement les projets configurés. Les réglages restent accessibles sans connexion au serveur Hindsight.

## Dossier commun et archives à part

La vue d’accueil lit le catalogue du dossier sélectionné ; la collecte reste pilotée par
`collect.py` et sa configuration `projects.toml`, réutilisables pour plusieurs projets et dépôts.
**Ouvrir le dossier** donne accès aux archives et à cette configuration. Le catalogue se filtre
par projet, dépôt, famille et texte ; la recherche inclut les identifiants d’origine et la provenance.

Les enregistrements classés `internal_review` (validations internes de Codex) et `empty_export`
(exports vides ou interrompus) sont conservés sous **Archives à part**, replié par défaut.
Ils ne comptent pas dans les sources du projet à traiter. Le titre d’une conversation ne décide
jamais de ce classement. Les filtres s’appliquent aussi aux archives, dont le texte reste consultable.

**Collecter les sources** attend une confirmation et ne déclenche aucun traitement Hindsight.
Codex et Claude Code passent par Agent Dump, sans import natif maison. Les traitements de mémoire
et l’import manuel Hermes restent accessibles séparément. La date d’une source est prioritaire
sur sa date d’archivage ; une date de collecte utilisée en secours est explicitement étiquetée.

### Documents ajoutés à la main

Depuis **Dossier mémoire → Ajouter des documents**, choisir des fichiers `.md`, `.tex` ou `.pdf`, puis leur projet. Après confirmation, `collect.py --project ID --import-file PATH` copie les originaux dans `documents/<projet>/` et indexe uniquement ces documents dans le catalogue commun. Les collecteurs de conversations/GitHub/W&B/benchmarks ne sont pas lancés. Les projets proviennent de la configuration publiée dans le catalogue ; les anciens catalogues restent compatibles.

Le Markdown est lisible dans l’app ; le TeX est affiché tel quel ; un PDF s’ouvre avec le lecteur local. Aucun traitement Hindsight, extraction PDF ou compilation TeX. Réimporter le même chemin met à jour la copie ; des noms identiques provenant de chemins différents restent distincts. Les sources originales ne sont pas modifiées.

### Validation des envois de mémoire

La synchronisation du projet présente les identifiants de chaque document avant confirmation. Le script `sync.py` lie cette confirmation au contenu et aux métadonnées précis du plan : si le plan ou le script change, il faut préparer un nouvel aperçu. Des identifiants peuvent être saisis un par ligne dans la section avancée pour limiter le lot. La file doit être lisible et vide à la préparation et à la confirmation.

Les envois de fichiers suivis et les imports Hermes affichent aussi la liste avant validation. La synchronisation automatique des dossiers est suspendue, y compris pour les anciens réglages déjà activés. Ces protections ne contrôlent pas les autres clients ou appels directs à l’API Hindsight.

## Actualiser la mémoire

La vue **Mémoire** rassemble le dossier commun et la banque sélectionnée. Les filtres par projet,
dépôt, type et état permettent de voir les sources **à ajouter**, **à jour**, **modifiées**,
**en cours**, **exclues**, ou les documents dont la **source reste à relier**. La comparaison
porte sur le texte envoyé, et ne déduit pas la fraîcheur d’une date de collecte.

1. Ajouter des fichiers depuis l’app ou utiliser les collecteurs déjà configurés.
2. Inclure ou exclure les sources, individuellement ou pour le filtre courant.
3. **Actualiser le dossier** lance uniquement la collecte et met à jour le catalogue local.
   Cette action fonctionne sans banque sélectionnée et sans contacter Hindsight.
4. **Préparer l’envoi à Hindsight** compare les fichiers déjà collectés à la banque et présente
   tous les ajouts et changements des sources activées. La collecte n’est pas relancée ; le
   catalogue peut être utilisé même si le collecteur est absent. Aucun envoi avant **Envoyer**.
5. Après validation, le texte complet est envoyé avec des identifiants stables ; les sources
   modifiées remplacent leur version précédente. Les PDF nécessitent une source TeX ou Markdown.

**Retirer** demande confirmation, sauvegarde le document, le retire de Hindsight et exclut ses
futurs envois en conservant le fichier local. Désactiver seulement une source conserve sa version
mémorisée. Les décisions de l’audit et les cas différés restent protégés. Les documents ajoutés
par d’autres outils sont visibles et peuvent être reliés explicitement à une source locale.

La collecte est déclenchée sur demande, sans nouvelle automatisation. Un envoi interrompu n’est
pas répété aveuglément : la reprise explicite réutilise le lot et son identifiant d’origine.
L’app ne lance pas de consolidation ni de rafraîchissement des synthèses dans ce parcours ;
les éventuels traitements automatiques restent ceux des réglages du serveur.
Les choix et le suivi des envois sont conservés par banque dans
`collection/.memory-workspace.json`, les lots de reprise dans `collection/.memory-operations/`.

La mention **À jour** compare l’identifiant du document et l’empreinte du texte complet.
Ces sources sont automatiquement écartées des prochains aperçus. Un lot marqué terminé par
le serveur peut avoir seulement créé ses tâches d’extraction : les sources non encore enregistrées
restent **En cours** tant que les tâches de mémorisation continuent. Un vrai échec reste visible
et exige une nouvelle validation. Le suivi des anciennes fausses erreurs est récupéré depuis
les lots sauvegardés, sans nouvel envoi, avec sauvegarde préalable dans
`collection/.memory-workspace.pre-tracking-v2.json`.
