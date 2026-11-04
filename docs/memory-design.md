# Piloter la structure de la mémoire Hindsight

Recherche du 2026-10-19 : comment décider **ce qui est retenu**, **ce qui compte**, **l'objectif** d'une
banque, et sous quelle forme (un « prompt »). Sources : code amont `hindsight-api-slim`
(`hindsight_api/config.py`, `engine/audit.py`, `api/http.py`), contrat `docs/openapi.json` (API 1.0.0),
documentation publique de Hindsight.

## En bref

Oui, avec des **missions** (texte libre injecté dans les prompts) et, si besoin, un vrai **prompt
d'extraction**. Ces réglages sont **propres à chaque banque** : ce sont des surcharges posées par
`PATCH /v1/default/banks/{id}/config`, qui l'emportent sur la configuration du serveur. Ils
s'appliquent aux **prochaines** extractions et consolidations ; les faits existants ne changent pas
tant qu'un document n'est pas retraité.

Dans l'app, tout est dans la section **Structure de la mémoire**, avec un **essai à blanc**
(`POST …/memories/dry-run-extract`, qui accepte les réglages non enregistrés) pour voir les faits produits
avant d'enregistrer.

## Les leviers, du plus important au plus fin

| Étape | Réglage (clé de configuration) | Effet |
|---|---|---|
| Extraction | `retain_mission` | **Ce qui mérite d'être retenu.** Injecté dans le prompt d'extraction quel que soit le mode. C'est le levier principal de l'« importance ». |
| Extraction | `retain_extraction_mode` | `concise` (défaut), `verbose`, `custom`, `verbatim`, `chunks` (pas d'extraction LLM). |
| Extraction | `retain_custom_instructions` | Le **prompt** d'extraction, utilisé seulement en mode `custom` à la place des consignes par défaut (la structure de sortie reste imposée). |
| Extraction | `entity_labels`, `entities_allow_free_form` | Vocabulaire contrôlé : dimensions (`value`, `multi-values`, `text`, `multi-text`, `map`) et valeurs permises. Avec `tag: true`, la valeur devient un tag `clé:valeur` : filtrable, et **périmètre de consolidation**. |
| Extraction | `retain_chunk_size`, `retain_strategies`, `retain_default_strategy` | Taille des morceaux ; stratégies nommées (jeux de réglages choisis par requête). |
| Consolidation | `enable_observations`, `enable_auto_consolidation` | Couche d'observations au-dessus des faits ; consolidation après chaque rétention. |
| Consolidation | `observations_mission` | **Ce que les observations doivent capturer** (synthèse, tendances, ce qui remplace quoi). |
| Consolidation | `max_observations_per_scope`, `consolidation_strategies` | Plafond par périmètre de tags ; stratégies par périmètre, chacune avec sa propre mission (ex. un périmètre partagé qui ne nomme personne). |
| Réponses | `reflect_mission` | Objectif de la banque **quand elle répond** (reflect, modèles mentaux). Sans effet sur l'extraction. |
| Réponses | `disposition_skepticism`, `_literalism`, `_empathy` (1–5) | Style de raisonnement de reflect. |
| Réponses | Directives (`…/directives`) | Règles impératives de reflect (langue, format, interdits), avec priorité et tags. |
| Réponses | Modèles mentaux (`…/mental-models`) | Synthèses épinglées, rafraîchies par le LLM ; consultées en premier par reflect. |
| Lecture | `enable_text_search`, `enable_temporal_retrieval`, `enable_graph_retrieval`, `enable_reranking` | Branches du pipeline de recall. |
| Données | `store_document_text` | Garder ou non le texte source (minimisation). |
| Sécurité | `memory_defense` | Politique contre l'empoisonnement de la mémoire (format `DefensePolicy`). |

Hindsight n'a **pas de score d'importance réglable** par fait. L'importance s'exprime à l'extraction
(mission de rétention, prompt du mode `custom`, vocabulaire), puis à la consolidation (mission des
observations, stratégies par périmètre). Les **tags** comptent doublement : ils filtrent les recherches et
séparent les périmètres de consolidation.

Les modèles LLM utilisés par chaque rôle restent des réglages du serveur (variables d'environnement) : voir
la section « Modèles & serveur ».

## Lectures : qui a lu quoi et quand

- Le journal d'audit (`audit_log_enabled`, activable par banque) enregistre chaque accès : action,
  transport, requête et **réponse complète** (pour un recall : les faits renvoyés). L'app en tire l'onglet
  **Lectures** et les « faits les plus lus ».
- Pour les appels **HTTP**, le serveur n'enregistre **aucune identité** (ni client, ni user-agent, ni IP :
  voir `_make_audited_http` dans `api/http.py`). Seuls les clients **MCP** sont nommés. L'app regroupe donc
  les appels HTTP par **signature de requête** (réglages propres à chaque intégration) et permet de nommer
  chaque signature. Pour une identification native, connectez les agents en MCP.
- Le serveur 1.0.0 ne tient pas d'historique par fait. À partir de 1.1.0, `GET …/documents/{id}/history`
  liste ce qui a changé un document et ses faits (envois, retraitements, tags et portée, faits modifiés,
  consolidations) : le lecteur de document l'affiche sous son en-tête.
- Pour un reflect, les traces LLM du moment montrent les faits réellement fournis au modèle. Elles sont
  conservées 1 jour par défaut (`HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS`).

## Coûts

Les traces LLM donnent, par appel, le modèle et les jetons (entrée, sortie, cache, réflexion). L'app :

- les valorise avec une grille tarifaire modifiable (Réglages › Tarifs) ;
- traite les fournisseurs par **abonnement** (`claude-code`, `openai-codex`) comme du quota plutôt que de
  l'argent, avec leur équivalent à l'usage ;
- garde un historique local des compteurs (sans contenu), au-delà de la rétention du serveur ;
- estime le coût **avant** une action (import, retraitement, consolidation, reflect, modèle mental). Elle
  part de la moyenne par appel observée sur la banque, sinon de valeurs par défaut, et donne une
  fourchette.

Ne sont pas comptés : embeddings, reranker et modèle de décision. Le serveur 1.0.0 ne les trace pas ; à partir
de 1.1.0, `/llm-requests` les enregistre aussi (reconnaissables à leur `scope` : `embedding_*`, `rerank`,
`decision_*`), et l'app ne lit que les appels LLM (`call_type=llm`), hors quotas, plafonds et estimations.
Avec un serveur 1.2.0, l'écran Consommation montre à part ces appels sur 7 jours, toutes banques, par modèle
(`/llm-requests/stats` avec `call_type` et `split_by=model`, relu au plus toutes les 5 min). Seuls les modèles
Hindsight Inference (`hs-decide-1-flash`, `hs-rerank-1`, `hs-embed-1`) sont chiffrés, à l'entrée seulement ;
chargés en local, ils portent le nom de leur dépôt (`hindsight-ai/hs-rerank-1`) et restent gratuits.

## Fusion et renommage

- **Fusion** : `POST …/transfer/export` sur la source, puis `POST …/transfer/import?mode=merge` sur la
  cible, sans LLM : faits ré-embarqués, entités re-résolues. Les conflits d'identifiants de documents sont
  réglés par `document_conflict` (`skip`, `replace` ou `new-id`).
- **Renommer** : nom affiché (`PATCH /banks/{id}`), alias affiché (`POST …/aliases` avec `primary: true`),
  ou nouvel identifiant (clone, suppression de l'ancien, ancien id conservé comme alias).

## Sources externes

- Documentation Hindsight : [Best Practices](https://hindsight.vectorize.io/best-practices),
  [Hindsight Cloud](https://docs.hindsight.vectorize.io),
  [API](https://hindsight.vectorize.io/api-reference),
  [0.8.5 (audit par banque)](https://hindsight.vectorize.io/blog/2026/07/21/version-0-8-5)
- Article : [Hindsight is 20/20](https://arxiv.org/html/2512.12818v1)
- Hermes Agent (format des sessions) : [Session Storage](https://hermes-agent.nousresearch.com/docs/developer-guide/session-storage)
  et `hermes_state*.py` du dépôt `NousResearch/hermes-agent`
