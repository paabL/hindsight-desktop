> Archive technique : le lecteur natif Codex a été retiré le 29 octobre 2026.
> Les nouvelles conversations sont exportées par Agent Dump dans le dossier commun.

# Format réel des sessions Codex (`~/.codex/sessions`)

Relevé fait le 2026-10-18 sur un Mac réel, en **lecture seule**, par analyse de la *structure* (noms de clés,
types JSON, valeurs d'énumération). Aucun texte de conversation n'est reproduit ici. La fixture
[`Tests/HindsightCoreTests/Fixtures/codex/sample-rollout.jsonl`](../Tests/HindsightCoreTests/Fixtures/codex/sample-rollout.jsonl)
est une session **fabriquée** (19 lignes) qui reprend exactement les clés, les types et l'ordre des événements d'une
vraie session ; tous les textes, ids, chemins et horodatages y sont fictifs, et l'image est un PNG 1×1.

Corpus examiné : 2 084 fichiers (2 061 dans `sessions/`, 23 dans `archived_sessions/`), 77 valeurs de `cli_version`
différentes (de `0.35.0` à `0.163.0`), 0 ligne JSON invalide.

## 1. Emplacement et fichiers

| Point | Constat |
|---|---|
| Dossiers | `~/.codex/sessions/AAAA/MM/JJ/rollout-<date>-<uuid>.jsonl[.zst]` et `~/.codex/archived_sessions/` (à plat, `.jsonl.zst` seulement) |
| Nombre | 411 `.jsonl` bruts, 1 650 `.jsonl.zst` dans `sessions/` ; 23 `.jsonl.zst` dans `archived_sessions/` |
| Taille | `.jsonl` : 47 Ko à 241 Mo (médiane 451 Ko) ; `.jsonl.zst` : 1 Ko à 39,6 Mo (médiane 91 Ko) |
| Autres fichiers | aucun sous `sessions/` ; `~/.codex/history.jsonl`, `attachments/`, `generated_images/` sont d'autres choses (non analysées) |
| Format | **JSON Lines**, un objet par ligne, UTF-8 |
| Compression | **~80 % des sessions sont en Zstandard** (`.jsonl.zst`), les plus anciennes comme les plus récentes |

**Compression : point bloquant pour l'app.** Le framework *Compression* d'Apple ne sait pas décoder le zstd
(algorithmes disponibles : LZ4, zlib, LZMA, Brotli, LZFSE, LZBITMAP, et deux nouveaux en macOS 27). Lire les
sessions compressées demande donc soit un décodeur zstd embarqué (contraire à « aucune dépendance tierce »), soit
d'appeler un binaire `zstd` externe (présent ici via Homebrew et Anaconda, mais rien ne garantit sa présence
ailleurs). À trancher avant d'écrire l'import.

**Nom de fichier.** `rollout-AAAA-MM-JJThh-mm-ss-<uuid>` : la date et l'heure sont en **heure locale** de la machine
au démarrage (écarts constatés par rapport à l'horodatage UTC du `session_meta` : −5, −4, +1, +2 h selon la date).
Il ne faut donc pas s'en servir comme horodatage fiable. L'`<uuid>` est égal à `payload.id` du `session_meta`
dans 2 061 cas sur 2 082 (voir § 6).

## 2. Deux « époques » de format

| Époque | Fichiers | Ligne type |
|---|---|---|
| **Enveloppé** (tout le corpus sauf 2 fichiers) | 2 082 | `{timestamp, ordinal, type, payload, [metadata]}` |
| **Plat** (sessions du 2025-09-04 seulement) | 2 | pas d'enveloppe : la première ligne est `{id, timestamp, instructions, git}`, puis des lignes `{record_type}` (`"state"`) et des éléments directs `{type: message / reasoning / function_call / function_call_output, …}` |

L'ancien format plat n'a ni `ordinal`, ni `payload`, ni horodatage par ligne, ni événements `event_msg`. Il ne
concerne que 2 fichiers (~75 Ko chacun) : il est raisonnable de les ignorer, en signalant « format non géré ».

## 3. Enveloppe (format courant)

Clés de premier niveau, dans cet ordre : `timestamp`, `ordinal`, `type`, `payload`, et parfois `metadata`.

| Clé | Type | Remarque |
|---|---|---|
| `timestamp` | string | ISO 8601 **UTC**, millisecondes, suffixe `Z` (24 caractères) |
| `ordinal` | int | numéro de ligne dans la session, à partir de 0, strictement croissant (une seule rupture de continuité vue sur 339 sessions échantillonnées) |
| `type` | string | voir § 4 |
| `payload` | object | contenu ; sa clé `type` en sous-type quand elle existe |
| `metadata` | object | présent surtout sur les `response_item` ; `client_authored` (bool), `user_input_order` (int), `fallback_token_limit_override` (int), `retained_source` (object), `mcp_attribution` (object) |

### Où trouver l'essentiel

| Information | Emplacement |
|---|---|
| Id de la session | `session_meta.payload.id` (= uuid du nom de fichier) ; `payload.session_id` = id de la **session racine** |
| Horodatage de départ | `session_meta.payload.timestamp` (identique au `timestamp` de la ligne) |
| Répertoire de travail | `session_meta.payload.cwd` (au démarrage) ; puis `turn_context.payload.cwd` **à chaque tour** (peut changer) ; aussi `event_msg/thread_settings_applied.payload.thread_settings.cwd` |
| Version de Codex | `session_meta.payload.cli_version` (string) |
| Application d'origine | `session_meta.payload.originator` : `codex_vscode`, `codex_work_desktop`, `Codex Desktop`, `codex-tui`, `codex_exec`, `codex-chrome-extension-sidepanel`, `zed`, `openclaw`, `hermes` |
| Modèle | `turn_context.payload.model`, `session_meta.payload.model_provider` (string ou `null`) |

## 4. Types d'événements

Les comptes sont ceux du corpus entier (format enveloppé).

| `type` | `payload.type` | Nombre | Rôle |
|---|---|---:|---|
| `session_meta` | — | 2 162 | en-tête (normalement 1 par fichier ; 2 162 lignes pour 2 082 fichiers, voir § 6) |
| `event_msg` | `item_completed` | 244 370 | élément terminé (message, commande, fichier modifié, appel MCP, raisonnement, sous-agent…), voir § 5.4 |
| | `token_count` | 136 315 | compteurs de jetons et limites d'usage |
| | `task_started` / `task_complete` | 16 584 / 16 238 | début et fin d'un **tour** |
| | `thread_settings_applied` | 13 400 | réglages du fil (cwd, modèle, permissions…) |
| | `turn_aborted` | 303 | tour interrompu (`reason`, ex. `interrupted`) |
| | `thread_goal_updated` | 46 | objectif du fil mis à jour |
| `response_item` | `message` | 53 464 | message (rôles `user`, `assistant`, `developer`) |
| | `reasoning` | 117 019 | bloc de raisonnement (contenu chiffré) |
| | `custom_tool_call` / `custom_tool_call_output` | 61 751 / 61 766 | appel d'outil « libre » (`exec`, `apply_patch`) et sa sortie |
| | `function_call` / `function_call_output` | 36 009 / 36 275 | appel de fonction (JSON) et sa sortie |
| | `agent_message` | 13 179 | message d'un autre agent (contenu chiffré) |
| | `compaction` | 809 | compactage du contexte (contenu chiffré) |
| | `web_search_call` | 76 | recherche web |
| | `tool_search_call` / `tool_search_output` | 10 / 10 | recherche d'outils différés |
| | `additional_tools` | 50 | catalogue d'outils ajouté |
| `turn_context` | — | 34 153 | contexte d'un tour (cwd, modèle, sandbox, permissions…) |
| `token_usage_record` | — | 75 195 | usage de jetons par réponse |
| `world_state` | — | 3 324 | instantané de l'environnement et des outils disponibles |
| `compacted` | — | 769 | résultat d'un compactage (historique de remplacement) |
| `inter_agent_communication_metadata` | — | 10 398 | métadonnée entre agents (`trigger_turn` bool) |
| `retained_context` | `verified_answer` | 119 | réponses validées à des questions |
| `realtime_item` | `transcript_segment` (72), `realtime_session_started` (9), `realtime_session_closed` (9), `bem_item_promoted` (3) | 93 | sessions vocales |

Les types sans `payload.type` (`session_meta`, `turn_context`, `token_usage_record`, `world_state`, `compacted`,
`inter_agent_communication_metadata`) portent directement leurs champs dans `payload`.

## 5. Détail par famille

Types JSON : `string`, `int`, `float`, `bool`, `null`, `object`, `array`. `[]` = élément de tableau.

### 5.1 `session_meta`

`payload` : `id` string, `session_id` string, `timestamp` string, `cwd` string, `originator` string, `cli_version` string,
`source` (string **ou** object, voir § 6), `thread_source` string, `model_provider` string|null, `history_mode` string
(`paginated`), `base_instructions` object|null (`text` string, `provenance` {`type`, `model`}), `context_window`
{`window_id`}, `git` object (`branch`, `commit_hash`, `repository_url`), et, selon les versions : `creator_account_id`,
`creator_user_id`, `memory_mode`, `multi_agent_version`, `runtime_workspace_roots` array<string>, `dynamic_tools` array,
`parent_thread_id`, `forked_from_id`, `forked_from_ordinal_exclusive` int, `subagent_history_start_ordinal` int,
`history_base` object, `agent_nickname`, `agent_path`. **70 combinaisons de clés** différentes ont été observées
(2 082 en-têtes) : aucune clé de `session_meta` n'est garantie, hormis `id`, `timestamp`, `cwd`, `originator`,
`cli_version`, `history_mode`.

### 5.2 `response_item/message` — le cœur des échanges

`payload` : `type` (`message`), `id` string, `role` (`user` | `assistant` | `developer`), `content` array,
`phase` (assistant seulement : `commentary` | `final_answer`), `internal_chat_message_metadata_passthrough` object
(`turn_id` string, `create_time` float, `content_item_kinds` array<string>).

**Blocs de `content[]`** (clé `type`) :

| Rôle | Bloc | Clés |
|---|---|---|
| `user`, `developer` | `input_text` | `text` |
| `user` | `input_image` | `image_url` string, `detail` string (`high`) |
| `assistant` | `output_text` | `text` |

Dans tout le corpus : 311 393 blocs `input_text` utilisateur, 28 198 `output_text` assistant, 81 `input_image`.
`agent_message` utilise en plus un bloc `encrypted_content`.

**Distinguer ce que l'utilisateur a réellement tapé.** Les messages de rôle `user` contiennent aussi du texte
**injecté par Codex** (contexte d'environnement, instructions `AGENTS.md`, rappels…). Le discriminant fiable est
`internal_chat_message_metadata_passthrough.content_item_kinds`, un tableau **parallèle** à `content[]` (une entrée
par bloc) :

- texte tapé : `user.text` ; image jointe : `user.image` ;
- injections : `environments.environment_context`, `agents_md.instructions`, `permissions.instructions`,
  `host_skills.instructions`, `plugins.recommendations`, `plugins.usage_instructions`, `apps.instructions`,
  `images.resize_notice`, `multi_agent.*`, `collaboration_mode.instructions`, `memories.instructions`,
  `guardian.*`, `additional_content.*`, `model_switch.instructions`, `model.base_instructions`,
  `generic.developer_instructions`, `generic.turn_aborted`, `user.heartbeat`, `tools.deferred_namespaces`… ;
- côté assistant : le plus souvent `unknown`.

**Ce champ n'existe qu'à partir de Codex `0.150`** : toutes les sessions plus anciennes (la majorité du corpus) ne l'ont
pas. Pour elles, il faut une heuristique, par exemple « bloc ne commençant ni par une balise `<…>` ni par `# AGENTS.md` »
(non validée ici). Sur un échantillon, les messages utilisateur
commencent par 1 à 3+ blocs `user.text` ; un même message peut mêler texte tapé et blocs injectés.

### 5.3 Images

**Forme : data URI base64 en ligne** (`data:image/png;base64,…`), dans le bloc `input_image.image_url`. Aucun chemin,
aucune URL distante n'a été rencontré (81 images sur tout le corpus, toutes en `data:image/png`). Une image pèse de
quelques dizaines de Ko à plusieurs centaines de Ko en base64 : une ligne peut dépasser 700 000 caractères.

Un message avec image a cette séquence de blocs, avec `content_item_kinds` correspondant :

1. un ou plusieurs `input_text` (`user.text`) ;
2. un `input_text` d'**ouverture** de forme `<image name=[Image #N] path="…">` (`user.text`) — l'attribut `path` est un
   **chemin temporaire local** (presse-papiers) qui n'existe peut-être plus ;
3. le bloc `input_image` (`user.image`) ;
4. un `input_text` valant exactement `</image>` (`user.text`).

Redondance utile : l'événement `event_msg/item_completed` d'item `UserMessage` contient, lui, un bloc
`{type: "local_image", path}` (chemin local) à côté du bloc `{type: "text", text, text_elements}`.

Le texte `images.resize_notice` (message `developer`/`user` injecté) signale qu'une image a été redimensionnée.
Les **sorties d'outils** peuvent aussi contenir des images : voir `McpToolCall` (§ 5.4), avec `result.content[]`
de `{type, data, mimeType}` (`data` = base64). Ces dernières ne sont pas des `input_image`.

### 5.4 `event_msg/item_completed`

`payload` : `type`, `thread_id`, `turn_id`, `item` object, `started_at_ms` int, `completed_at_ms` int. La clé
`item.type` (valeurs en CamelCase) sert de sous-type :

| `item.type` | Clés propres |
|---|---|
| `UserMessage` | `id`, `client_id`, `content[]` : `{type: "text", text, text_elements}` ou `{type: "local_image", path}` |
| `AgentMessage` | `id`, `phase`, `content[]` : `{type: "Text", text}` (T majuscule) |
| `Reasoning` | `id`, `summary_text` array<string>, `raw_content` array |
| `CommandExecution` | `id`, `command` array<string>, `cwd`, `parsed_cmd[]`, `aggregated_output`, `stdout`, `stderr`, `formatted_output`, `exit_code` int, `duration` {`secs`,`nanos`}, `process_id`, `source`, `status` |
| `FileChange` | `id`, `changes` object **dont les clés sont des chemins de fichiers** → `{content, move_path (null), type, unified_diff}`, `stdout`, `stderr`, `status` |
| `McpToolCall` | `id`, `server`, `tool`, `pluginId`, `arguments` object (variable), `result` {`content[]`, `isError`, `_meta`}, `duration`, `readOnlyHint`, `status` |
| `WebSearch` | `id`, `query`, `action` {`type`, `query`, `queries[]`, `url`, `pattern`}, `results[]` {`title`, `url`, `snippet`, `domain`, `ref_id`, `type`} |
| `Plan` | `id`, `text` |
| `SubAgentActivity` | `id`, `kind` (`interacted`), `agent_path`, `agent_thread_id` |
| `CollabAgentToolCall`, `Extension`, `ContextCompaction` | clés variables, non détaillées |

Valeurs vues : `status` ∈ {`completed`, `failed`}, `phase` ∈ {`final_answer`, `commentary`}.

### 5.5 Appels d'outils (`response_item`)

| `payload.type` | Clés |
|---|---|
| `custom_tool_call` | `id`, `call_id`, `name` (`exec`, `apply_patch`), `input` **string** (code ou patch), `status` (`completed`) |
| `custom_tool_call_output` | `id`, `call_id`, `output` : **array de `{type: "input_text", text}` ou string** |
| `function_call` | `id`, `call_id`, `name`, `namespace` (optionnel), `arguments` **string JSON** |
| `function_call_output` | `id`, `call_id`, `output` **string** (parfois un tableau) |

Le lien appel ↔ sortie est `call_id`. Noms de fonctions fréquents : `exec_command`, `write_stdin`, `shell`,
`shell_command`, `send_message`, `update_plan`, `wait_agent`, `request_user_input`, `view_image`. Dans
`custom_tool_call_output`, les éléments `text` contiennent souvent eux-mêmes du **JSON sérialisé** (résultats de
cellules JavaScript).

### 5.6 `reasoning`

`payload` : `id`, `summary` array de `{type: "summary_text", text}` (souvent **vide**), `encrypted_content` string
(opaque). Le raisonnement lisible n'est quasiment jamais disponible ; seul `item_completed/Reasoning.summary_text`
peut en porter un résumé.

### 5.7 Événements de tour

- `task_started.payload` : `turn_id`, `root_turn_id`, `started_at` int (secondes), `model_context_window` int,
  `collaboration_mode_kind` (`default` | `plan`), `turn_attribution` {`turn_id`, `root_turn_id`, `parent_turn_id`
  (null), `initiating_agent_path` (null), `turn_trigger`}.
- `task_complete.payload` : `turn_id`, `root_turn_id`, `started_at`, `completed_at` (secondes), `duration_ms`,
  `time_to_first_token_ms`, `last_agent_message` string.
- `turn_trigger` ∈ {`composer`, `guardian_review`, `app_tool_send_message`, `app_tool_create_thread`,
  `plan_implementation`, `automation_heartbeat_scheduled`, `goal`, `send_user_message_async_question`,
  `chatgpt_handoff`} ; la clé n'apparaît qu'à partir de Codex `0.162` (et pas dans tous les tours de cette version).
- `turn_context.payload` : cwd, modèle, `approval_policy`, `sandbox_policy`, `permission_profile`, `timezone`,
  `current_date`, `workspace_roots`, `personality`, `effort`, etc. (très verbeux, ~5 Ko par ligne).

### 5.8 Types inconnus ou à ignorer pour un import de conversation

`token_count`, `token_usage_record`, `thread_settings_applied`, `world_state`, `turn_context`, `compacted`,
`compaction`, `additional_tools`, `tool_search_*`, `inter_agent_communication_metadata`, `realtime_item/*`,
`retained_context/*` : aucune ne porte de texte d'échange nécessaire. Ils sont présents dans la fixture
(`world_state`, `token_usage_record`) pour tester qu'un lecteur **ignore sans échouer** un type qu'il ne connaît pas :
de nouveaux types apparaissent d'une version de Codex à l'autre.

## 6. Ambiguïtés et variabilités à connaître

1. **Une « session » n'est pas une « conversation ».** Parmi les 2 082 en-têtes, `thread_source` vaut `guardian_review`
   (1 018 fichiers : revues automatiques de sécurité, sans valeur de conversation), `subagent` (268), `user` (263),
   absent (503, versions anciennes), `chatgpt_handoff` (11), `realtime_voice` (9), `voice_chat` (6),
   `agent_created_thread` (4). Seule une minorité correspond à une vraie conversation de l'utilisateur. Un import doit
   filtrer ; `thread_source` absent est à traiter comme « utilisateur probable ».
2. **Les sous-agents et revues sont des fichiers séparés**, reliés par `parent_thread_id` ; `session_id` (racine) est
   alors différent de `id`. `forked_from_id` (+ `forked_from_ordinal_exclusive`, `subagent_history_start_ordinal`)
   indique un fil copié depuis un autre : le début du fichier **pourrait** rejouer l'historique du parent, d'où un risque de
   doublons si on importe parent et fils (*déduit des noms de clés, non vérifié sur des données*).
3. **`source` a deux formes** : string (`vscode`, `cli`, `exec`) ou objet (`{subagent: {other: string}}`,
   `{subagent: {thread_spawn: object}}`).
4. **Notion de « tâche ».** Un tour = `task_started` … `task_complete` (ou `turn_aborted`). Sur un échantillon de
   2 346 tours (339 sessions de moins de 8 Mo) : 690 n'ont **aucun** message `user.text` (reprise automatique, heartbeat, relance d'un autre agent),
   1 457 en ont un, 199 en ont deux ou plus (consignes complémentaires en cours de tour). Les tâches `NNN` de la banque
   actuelle sont donc à définir : par tour, ou par message utilisateur.
5. **Messages en double.** Chaque message apparaît deux fois : `response_item/message` et `event_msg/item_completed`
   (`UserMessage`, `AgentMessage`). Les comptes diffèrent légèrement (ex. 6 vs 6 côté utilisateur, 15 vs 14 côté
   assistant sur la session analysée) ; il faut choisir **une** source. `response_item` porte `role`, `phase` et
   l'image en ligne ; `item_completed` porte l'image comme chemin local et les horodatages de début/fin en ms.
6. **Id ≠ nom de fichier** dans 21 fichiers sur 2 082 ; et `session_meta` apparaît plus d'une fois dans certains
   fichiers (2 162 lignes pour 2 082 fichiers ; cause non élucidée, peut-être des fils copiés). Ne pas supposer l'unicité ; lire le premier.
7. **Horodatages hétérogènes** : ISO UTC (ms) sur chaque ligne, mais `started_at`/`completed_at` en **secondes**,
   `*_at_ms` en **millisecondes**, `create_time` en secondes flottantes, `resets_at` en secondes.
8. **Variance de schéma.** Les clés optionnelles sont nombreuses (`metadata`, `phase`, `namespace`, `turn_attribution`,
   `content_item_kinds`…). Il faut décoder de façon tolérante (tout optionnel, valeurs d'énumération ouvertes). La casse
   est incohérente d'une famille à l'autre : `item_completed/UserMessage.content[].type` vaut `text`, alors que
   `item_completed/AgentMessage.content[].type` vaut `Text` (majuscule) dans toutes les versions testées.
9. **Contenu chiffré** : `reasoning.encrypted_content`, `agent_message.content[].encrypted_content`,
   `compaction.encrypted_content` sont opaques et ne peuvent pas être importés.
10. **Texte injecté très volumineux.** Les premières lignes d'une session contiennent des instructions (plusieurs Ko par
    message `developer`, `world_state`, `turn_context`) : elles ne font pas partie de la conversation.
11. **Chemins personnels partout** : `cwd`, `workspace_roots`, clés de `FileChange.changes`, attribut `path` des balises
    `<image …>`, commandes. L'import devra décider quoi garder ; ces valeurs sont réelles dans les vrais fichiers.
12. **Taille.** Jusqu'à 241 Mo pour un `.jsonl` (et 39,6 Mo compressé) : lire en flux, ligne par ligne, sans charger le
    fichier entier ; certaines lignes dépassent 700 000 caractères (images).
13. **Sessions plates (2025-09-04)** : voir § 2 ; aucune autre session du corpus n'est dans ce format.
14. **Non vérifié** : le comportement d'une session en cours d'écriture (dernière ligne partielle), les fichiers
    `.jsonl.zst` tronqués, et `~/.codex/history.jsonl`. Les sessions de décembre 2025 à octobre 2026 sont les mieux
    représentées dans l'échantillon détaillé.
