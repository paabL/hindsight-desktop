# Interface Hindsight Desktop

L’unique interface de l’application est dans `desktop/src/` : React, TypeScript et CSS,
embarqués dans Tauri. Les anciennes cibles SwiftUI et leur vérification par stubs ont été retirées.

## Direction visuelle

- Surfaces froides, accent bleu-pétrole, eucalyptus et indigo : navigation, catégories et états distincts.
- Typographie système, hiérarchie nette, bordures discrètes, rayons mesurés.
- Pas d’orange, de décorations ludiques, d’illustrations marketing ni de slogans.
- Thèmes sombre et clair ; choix enregistré sur l’appareil.
- Données réelles, provenance et état des traitements au premier plan.

Les valeurs de référence sont dans `desktop/src/tokens.css`. Les composants communs
(boutons, cartes, badges, erreurs, fenêtres, typographie) sont dans `desktop/src/ui.tsx`.

## Navigation

Cinq vues principales : Dossier mémoire, Synthèses, Recherche, Documents et Consommation.
Avancé regroupe Vue d’ensemble, Structure de la mémoire, Opérations, Activité & lectures,
Chronologie, Graphe, Import Hermes, Serveur & modèles et Administration.
La couverture des dossiers est un onglet de Documents ; les réglages restent accessibles en bas.

Le dossier mémoire présente le catalogue local avant traitement : projets, collecteurs, familles de
sources, filtres et lecture avec provenance. La banque choisie concerne les connaissances conservées
par Hindsight. Le catalogue local est indépendant de cette banque et reste consultable hors connexion.

Les documents ouvrent un lecteur avec texte, faits, historique et gestion. Les pièces jointes sont
chargées à leur place dans les blocs du moteur. La recherche dans le lecteur surligne les mots trouvés.

## Données et actions

`desktop/src/transport.ts` est l’entrée unique vers les commandes Tauri. La coque Rust dialogue
avec `HindsightBridge`, un processus enfant privé qui réutilise les ViewModels de `HindsightCore`.
L’interface n’a pas d’accès direct au disque, à Node ou à un shell. Les documents sont rendus sans HTML brut.

Les écritures et actions coûteuses affichent la confirmation produite par le moteur. L’identifiant de
confirmation actif et le texte requis sont revérifiés côté natif. La confirmation est consommée avant
l’action. Les changements de banque ou de serveur invalident les demandes en attente.

Une requête lente affiche l’activité et désactive les actions concernées. Les erreurs restent lisibles,
les listes vides expliquent comment démarrer et les informations absentes sont affichées comme inconnues.

## Accessibilité et raccourcis

- Boutons et champs nommés ; navigation au clavier et focus visible.
- Focus contenu dans les fenêtres ; Échap ferme la fenêtre supérieure.
- Respect de la préférence de réduction des animations.
- `⌘K` : navigation rapide ; `⌘R` : actualiser ; `⌘,` : réglages ; `⌘1…5` : vues principales.

Le mode exemple est activé explicitement et signale ses données fictives. Il ne remplace pas les
états d’erreur d’une connexion réelle.

## Intégrations

Le package Swift n’expose plus `HindsightUI` ni l’exécutable `HindsightMac`. Les consommateurs de
l’ancienne interface, dont NOMAD Studio, doivent adapter leur intégration à cette migration.
Les bibliothèques internes `HindsightAPI` et `HindsightCore` restent disponibles.

## Atlas de la mémoire

Le graphe dispose de deux modes, entités et faits. Les groupes suivent une optimisation locale de modularité pondérée sur les liens chargés ; leurs noms reprennent les sujets les plus connectés en privilégiant les libellés lisibles aux marqueurs techniques. Les couleurs distinguent les groupes, et la taille représente le degré dans la vue filtrée. Le nombre de mentions reste un indicateur séparé dans l’inspecteur.

Le voisinage à un ou deux degrés, la liste des passerelles et la recherche insensible aux accents donnent plusieurs entrées dans la mémoire. « Relier à… » calcule un chemin non orienté, le plus court en nombre de liens, avec les filtres actifs. L’absence de chemin dans l’échantillon n’est pas une preuve d’absence de relation dans la banque complète. Les faits renvoient à leur document source, y compris en mode faits.

Le placement est déterministe et ne change pas lors de l’inspection. Les libellés évitent les collisions et apparaissent surtout à la sélection, à la recherche et au survol. La molette zoome autour du pointeur, le fond se déplace au glisser, et le clavier permet de déplacer, zoomer et recadrer la carte. Les totaux serveur signalent l’échantillonnage. Pour les cartes de plus de 80 nœuds, la vue initiale regroupe les nœuds en cercles avec leur effectif et agrège les liens entre groupes (70 liaisons au plus). Un clic ouvre les membres du groupe ; le zoom déploie les nœuds. Le dessin détaillé adapte son budget entre 120 et 1 800 liens, en conservant les liens de la sélection et du parcours ; l’analyse garde tous les liens retenus.
