import Foundation

/// Aide contextuelle des boutons « ? » : ce que fait une fonction, au niveau d'un ingénieur ou d'un
/// chercheur, en quelques lignes. Markdown simple (gras, code) rendu par l'interface.
public enum HelpTopic: String, CaseIterable, Sendable, Identifiable {
    case retain, extractionMode, retainMission, customInstructions, entityLabels, chunking, storeDocumentText
    case observations, consolidationStrategies, reflectMission, disposition, directives, mentalModels
    case recall, recallArms, reflect, budget, factTypes, dates, tags, dryRun, memoryDefense
    case merge, rename, clone, transfer
    case audit, reads, llmTraces, costs
    case graph, invalidate, reprocess, service, updates, operations
    case consumption, pause, budgets, library

    public var id: String { rawValue }

    public var title: String { content.0 }
    public var body: String { content.1 }

    private var content: (String, String) {
        switch self {
        case .retain:
            return (
                "Rétention (retain)",
                """
                Pipeline d'ingestion d'un document : découpage en **morceaux** → **extraction LLM** de faits atomiques \
                (texte autonome, type, entités, dates, liens causaux) → **embeddings** → **résolution d'entités** \
                (fusion avec celles déjà connues) → liens du graphe. Puis, si activée, **consolidation** en observations.
                Ce qui devient un fait dépend de la mission de rétention, du mode d'extraction et du vocabulaire \
                d'entités : ce sont les leviers de « ce qui est retenu ».
                """)
        case .extractionMode:
            return (
                "Mode d'extraction",
                """
                • `concise` (défaut) : faits essentiels, peu redondants.
                • `verbose` : plus de faits et de détails (plus de jetons, meilleur rappel).
                • `custom` : vos **instructions d'extraction** remplacent les consignes par défaut.
                • `verbatim` : passages conservés tels quels, sans reformulation.
                • `chunks` : pas d'extraction LLM ; les morceaux bruts sont indexés (recherche seule, coût minimal).
                """)
        case .retainMission:
            return (
                "Mission de rétention",
                """
                Spécification déclarative de **ce qui mérite d'être retenu**, injectée dans le prompt d'extraction \
                quel que soit le mode. C'est le moyen principal d'exprimer l'**importance** : écrivez ce qu'il faut \
                garder en priorité et ce qu'il faut ignorer. Hindsight n'a pas de score d'importance réglable : \
                l'importance se joue à l'extraction (mission), puis à la consolidation (mission des observations).
                """)
        case .customInstructions:
            return (
                "Instructions d'extraction (mode custom)",
                """
                Le « prompt » d'extraction : consignes libres utilisées **seulement en mode `custom`**, à la place \
                des consignes par défaut (la structure de sortie reste imposée par le serveur). Testez-les avec \
                l'essai à blanc avant d'enregistrer : un prompt trop restrictif fait perdre des faits.
                """)
        case .entityLabels:
            return (
                "Vocabulaire d'entités (étiquettes)",
                """
                Dimensions contrôlées attachées aux faits à l'extraction. Types : `value` (une valeur permise), \
                `multi-values`, `text` / `multi-text` (libres), `map` (champs). Avec **Tag**, la valeur devient aussi \
                un tag `clé:valeur` du fait : filtrable en recherche et **périmètre de consolidation**. \
                « Entités libres » laisse le LLM nommer d'autres entités hors vocabulaire.
                """)
        case .chunking:
            return (
                "Taille des morceaux",
                """
                Longueur (caractères) des morceaux envoyés à l'extraction ; une image « coûte » ~1 500 caractères. \
                Plus grand : plus de contexte par appel, moins d'appels, risque de faits manqués. Plus petit : \
                extraction plus fine, plus d'appels (coût).
                """)
        case .storeDocumentText:
            return (
                "Conserver le texte des documents",
                """
                Garde le texte source (documents et morceaux). Nécessaire pour le lecteur de documents, le retour \
                d'un fait à son passage et le retraitement. Le désactiver ne garde que les faits (minimisation des données).
                """)
        case .observations:
            return (
                "Observations (consolidation)",
                """
                Couche de connaissance consolidée au-dessus des faits bruts. Après chaque rétention, le LLM de \
                consolidation compare les nouveaux faits aux observations proches (recall interne) et décide de \
                **créer, mettre à jour ou fusionner** ; les quasi-doublons (cosinus ≥ 0,97) passent par une fusion \
                ciblée. Elles sont calculées **par périmètre de tags**. La **mission des observations** dit ce qu'elles \
                doivent capturer ; un plafond par périmètre limite leur nombre. Coûteuse en jetons sur les gros imports.
                """)
        case .consolidationStrategies:
            return (
                "Stratégies de consolidation (JSON)",
                """
                Réglages par périmètre : liste de `{"scopes": [{"tags": ["projet:*"], "tags_match": "all"}], \
                "observations_mission": "…", "max_observations_per_scope": 50}`. La première stratégie qui couvre un \
                périmètre l'emporte ; les valeurs absentes viennent des réglages de la banque. Ex. un périmètre \
                partagé qui ne garde que des tendances générales, sans nommer personne.
                """)
        case .reflectMission:
            return (
                "Mission (reflect)",
                """
                Identité et objectif de la banque **quand elle répond** (reflect, modèles mentaux). N'affecte ni \
                l'extraction ni recall.
                """)
        case .disposition:
            return (
                "Disposition",
                """
                Traits de raisonnement de reflect, de 1 à 5 : **scepticisme** (exigence de preuves, prudence face \
                aux affirmations), **littéralisme** (lecture au pied de la lettre vs interprétation), **empathie** \
                (prise en compte du ressenti et du contexte humain). Réglages « doux », contrairement aux directives.
                """)
        case .directives:
            return (
                "Directives",
                """
                Règles **impératives** injectées dans reflect (format, langue, interdits), avec priorité et tags \
                (une directive taguée ne s'applique qu'aux requêtes de ce périmètre). Elles ne changent pas ce qui \
                est retenu.
                """)
        case .mentalModels:
            return (
                "Modèles mentaux",
                """
                Synthèses épinglées : une requête source exécutée par reflect, dont le résultat est stocké et \
                **rafraîchi** (à la demande ou par déclencheur). reflect les consulte en premier, avant les \
                observations puis les faits. Chaque rafraîchissement appelle le LLM.
                """)
        case .recall:
            return (
                "Recall",
                """
                Recherche hybride **sans LLM génératif** : similarité sémantique (embeddings), plein texte (BM25), \
                parcours du **graphe** d'entités et de liens, et branche **temporelle** (dates de la requête) ; \
                fusion des rangs puis **reranking** par cross-encoder. Le budget règle l'effort d'exploration ; \
                `max_tokens` borne le volume renvoyé. Coût : embeddings + reranker (et modèle de décision s'il est réglé), \
                hors plafonds de dépense.
                """)
        case .recallArms:
            return (
                "Branches de recall",
                """
                Désactiver une branche la retire du pipeline (pas seulement de l'affichage) : texte = vecteurs seuls ; \
                sans temporel ni graphe = recherche plus « plate » ; sans reranking = plus rapide, ordre moins fin. \
                « Préférer les observations » remplace un fait brut par l'observation qui le résume.
                """)
        case .reflect:
            return (
                "Reflect",
                """
                Réponse rédigée par un **agent LLM** qui interroge la mémoire en boucle (outils : modèles mentaux → \
                observations → faits), sous la mission, la disposition et les directives de la banque. Le budget \
                borne l'exploration. Coût : plusieurs appels LLM, de quelques milliers à quelques dizaines de \
                milliers de jetons.
                """)
        case .budget:
            return (
                "Budget",
                """
                `low` / `mid` / `high` : profondeur d'exploration (nombre de nœuds du graphe parcourus en recall, \
                d'itérations en reflect). Plus haut = meilleur rappel, plus lent, plus coûteux pour reflect.
                """)
        case .factTypes:
            return (
                "Types de faits",
                """
                • **world** : faits sur le monde, les personnes, les projets.
                • **experience** : ce que l'agent a fait ou vécu (actions, échanges).
                • **observation** : connaissance consolidée à partir de plusieurs faits (voir Observations).
                """)
        case .dates:
            return (
                "Dates des faits",
                """
                `occurred_start/end` : quand l'évènement a eu lieu (extrait du texte, parfois relatif et résolu \
                par rapport à la date du document). `mentioned_at` : quand il a été mentionné (date du document). \
                La frise et la couleur « récence » utilisent l'une ou l'autre.
                """)
        case .tags:
            return (
                "Tags et périmètres",
                """
                Étiquettes libres des documents et faits. Elles servent de **filtre** (any / all / exact, strict ou \
                non) et définissent les **périmètres de consolidation** : des faits de tags différents ne sont pas \
                consolidés ensemble. Ajouter un tag change donc la structure des observations.
                """)
        case .dryRun:
            return (
                "Essai à blanc",
                """
                Extraction réelle par le LLM sur un extrait, avec les réglages **du brouillon**, sans rien écrire \
                dans la banque. Montre les faits qui seraient créés et les jetons consommés, d'où une projection \
                du coût sur un gros document.
                """)
        case .memoryDefense:
            return (
                "Défense de la mémoire (JSON)",
                """
                Politique du serveur contre l'empoisonnement de la mémoire (faits injectés, instructions cachées \
                dans les documents). Format `DefensePolicy`, validé par le serveur à l'enregistrement.
                """)
        case .merge:
            return (
                "Fusionner deux banques",
                """
                Export de la source (archive de transfert : documents, faits, entités, morceaux, pièces jointes) \
                puis import en mode `merge` dans la cible. **Sans LLM** : faits ré-embarqués avec le modèle de la \
                cible, entités re-résolues (fusionnées avec celles de la cible). Conflits d'identifiants : ignorer, \
                nouvel id, ou remplacer. Ni réglages, ni directives, ni modèles mentaux ne sont copiés ; lancez \
                ensuite une consolidation pour intégrer les faits aux observations de la cible.
                """)
        case .rename:
            return (
                "Renommer",
                """
                • **Nom affiché** : métadonnée, sans effet sur les clients.
                • **Alias affiché** : second identifiant qui mène à la même banque, montré à la place de l'id ; \
                rien n'est copié, l'ancien id fonctionne toujours.
                • **Changer l'identifiant** : clone sans LLM vers le nouvel id, suppression de l'ancien, puis \
                l'ancien id devient un alias (les agents existants continuent de fonctionner).
                """)
        case .clone:
            return (
                "Cloner",
                """
                Copie complète vers une nouvelle banque (export + import en une opération, sans LLM). Les deux \
                évoluent ensuite indépendamment. Attention : la configuration copiée inclut les webhooks.
                """)
        case .transfer:
            return (
                "Export / import",
                """
                Archive ZIP portable entre instances : documents, faits, observations, pièces jointes ; en option \
                configuration, directives, webhooks et journaux. Les embeddings ne sont jamais exportés : l'import \
                les recalcule avec le modèle de la cible.
                """)
        case .audit:
            return (
                "Journal d'audit",
                """
                Une entrée par accès : action (`recall`, `reflect`, `retain`…), transport (`http`, `mcp`, `system`), \
                requête, réponse (selon la version du serveur), client (`client_name`, user-agent). Activable par \
                banque ; rétention réglée côté serveur (`HINDSIGHT_API_AUDIT_LOG_RETENTION_DAYS`). Rien n'est \
                récupérable pour la période où il était désactivé.
                """)
        case .reads:
            return (
                "Lectures : qui a lu quoi",
                """
                Accès en lecture du journal d'audit : qui (client), quand, quelle question. Le serveur ne tient pas \
                d'historique par fait : quand la réponse n'est pas journalisée, **Rejouer** relance le même recall \
                (sur l'état ACTUEL de la mémoire, sans LLM génératif) ; pour un reflect, les **traces LLM** du \
                moment montrent les faits réellement fournis au modèle.
                """)
        case .llmTraces:
            return (
                "Traces LLM",
                """
                Chaque appel LLM du serveur : opération, modèle, jetons (entrée, sortie, cache, réflexion), durée, \
                prompt et réponse (tronqués). Conservées **1 jour par défaut** \
                (`HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS`) ; l'app en garde les compteurs dans son historique local.
                """)
        case .costs:
            return (
                "Consommation et coûts",
                """
                Mesuré : somme des jetons des traces LLM, valorisée par la grille tarifaire (Réglages › Tarifs, \
                prix publics indicatifs). Fournisseurs par **abonnement** (`claude-code`, `openai-codex`) : pas de \
                coût marginal, mais du quota ; l'équivalent à l'usage est indiqué. Estimé (avant une action) : \
                moyenne par appel observée sur cette banque, sinon valeurs par défaut, en fourchette. Embeddings, \
                reranker et modèle de décision (tracés depuis le serveur 1.1.0) ne sont pas comptés.
                """)
        case .graph:
            return (
                "Graphe",
                """
                Simulation de forces (attraction des liens, répulsion Barnes-Hut, centrage). Nœuds : faits ou \
                entités ; liens : entités partagées, liens temporels, sémantiques et causaux. Couleur : récence \
                (mention ou évènement), type ou importance (nombre de liens).
                """)
        case .invalidate:
            return (
                "Invalider un fait",
                """
                Le fait sort de recall, de la consolidation et de la maintenance du graphe, mais reste stocké pour \
                l'audit : opération **réversible**, contrairement à la suppression.
                """)
        case .reprocess:
            return (
                "Retraiter un document",
                """
                Supprime les faits du document puis relance l'extraction avec la configuration ACTUELLE (utile après \
                un changement de mission ou de mode). Les corrections manuelles de ces faits sont perdues ; appels \
                LLM et VLM.
                """)
        case .service:
            return (
                "Service Hindsight",
                """
                Agent launchd de votre session qui exécute le script de lancement : survit à la fermeture de l'app, \
                démarrage optionnel à l'ouverture de session, journal local. Le script n'est exécuté que s'il vous \
                appartient et n'est modifiable par personne d'autre ; un changement hors de l'app redemande votre accord.
                """)
        case .updates:
            return (
                "Mises à jour",
                """
                `git fetch` du dépôt d'origine, liste des commits, puis avance rapide sur le commit exact affiché, \
                recompilation et remplacement atomique de l'app. Transport chiffré exigé ; jamais d'écrasement d'une \
                copie locale modifiée.
                """)
        case .operations:
            return (
                "Opérations",
                """
                Tâches asynchrones du serveur (rétention, consolidation, export, import…) : statut, progression, \
                erreurs regroupées par cause. Une opération en échec peut être relancée ; la consolidation peut être \
                déclenchée à la main.
                """)
        case .consumption:
            return (
                "Consommation",
                """
                L'app relit les **traces LLM** de chaque banque (toutes les minutes, toutes les 10 s quand cet écran \
                ou la barre des menus est ouvert) et garde leurs compteurs, sans contenu, dans un historique local. \
                **Rythme** : moyenne des 5 dernières minutes. **Coût par document** : appels d'extraction portant la \
                métadonnée `document_id` ; la consolidation et reflect ne sont attribués à aucun document.
                """)
        case .pause:
            return (
                "Pause, gel et vidage",
                """
                L'API n'a pas de pause : trois niveaux s'en approchent.
                • **Pause** (une banque ou toutes) : l'app n'envoie plus rien et coupe la consolidation automatique \
                (`enable_auto_consolidation`, rétablie à la reprise). La file existante continue d'être traitée.
                • **Geler la file** : le service redémarre le serveur avec `HINDSIGHT_API_WORKER_ENABLED=false` \
                (environnement du service, pas votre script) ; l'API et les lectures restent disponibles, les \
                opérations attendent. Serveur lancé par l'app seulement.
                • **Vider la file** : annule les opérations en attente ; leur contenu devra être renvoyé.
                Au-delà, « Arrêter le serveur » coupe tout, lectures comprises.
                Les recherches avec reflect et les essais à blanc restent possibles : ils ne consomment qu'à votre \
                demande.
                """)
        case .budgets:
            return (
                "Plafonds",
                """
                **Facturé par jour** : fournisseurs à l'usage, grille de Tarifs, depuis minuit. L'app prévient \
                au seuil d'alerte, puis applique l'action choisie au dépassement, une \
                fois par franchissement : si vous reprenez à la main, elle ne remet pas en pause au relevé suivant. \
                L'action automatique se confirme une fois ; sans confirmation, l'app ne fait qu'alerter.
                """)
        case .library:
            return (
                "Documents",
                """
                Le **Dossier mémoire** montre les sources collectées avant traitement. Cet écran réunit une \
                **source** (fichier d'un dossier suivi) et les **documents** de la banque qui en viennent (métadonnées `repo` et `path`, ou \
                identifiant de session). **À jour** : empreinte identique à ce qui a été envoyé (date pour les PDF et \
                fichiers Office). **Modifié** : la source a changé depuis. **Non envoyé** : absent de la banque. \
                **Sans fait** : envoyé, rien d'extrait. **Fichier disparu** : en mémoire, plus sur le disque. \
                **En file** : une opération l'extrait. Les documents sans source suivie restent listés à part.
                """)
        }
    }
}
