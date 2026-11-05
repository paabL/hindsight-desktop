# Configuring Hindsight memory

Historical findings from 2026-10-19, with later notes for server 1.1 and 1.2. The
original review used upstream `hindsight-api-slim` (`hindsight_api/config.py`,
`engine/audit.py`, `api/http.py`), `docs/openapi.json` for API 1.0.0, and public
Hindsight documentation. This is a design reference, not a guarantee that every
server version exposes the same settings. Use the bundled API contract and
capability checks when implementing a change.

## Missions and extraction instructions

Missions are free text included in model prompts. A custom extraction prompt offers
finer control when needed. These settings are bank-specific overrides applied with
`PATCH /v1/default/banks/{id}/config`; they take precedence over server defaults.
They affect future extraction and consolidation. Existing facts do not change until
the relevant documents are reprocessed.

In the app, use Memory structure. Its dry run calls
`POST …/memories/dry-run-extract` with unsaved settings so you can inspect extracted
facts before saving the configuration. A dry run can still use model tokens and
requires confirmation.

## Configuration controls

| Stage | Configuration key | Effect |
|---|---|---|
| Extraction | `retain_mission` | Defines what is worth remembering. Included in every extraction mode; the main control for relevance. |
| Extraction | `retain_extraction_mode` | `concise` (default), `verbose`, `custom`, `verbatim`, or `chunks` (no LLM extraction). |
| Extraction | `retain_custom_instructions` | Replaces default extraction instructions in `custom` mode. The required output structure still applies. |
| Extraction | `entity_labels`, `entities_allow_free_form` | Controlled vocabulary with `value`, `multi-values`, `text`, `multi-text`, and `map` dimensions and permitted values. With `tag: true`, a value becomes a `key:value` tag used for filtering and consolidation scope. |
| Extraction | `retain_chunk_size`, `retain_strategies`, `retain_default_strategy` | Chunk size and named sets of settings selected per request. |
| Consolidation | `enable_observations`, `enable_auto_consolidation` | Observation layer above facts and consolidation after retention. |
| Consolidation | `observations_mission` | Defines what observations should capture: summaries, patterns, or superseded knowledge. |
| Consolidation | `max_observations_per_scope`, `consolidation_strategies` | Limit per tag scope and scope-specific strategies, each with its own mission. |
| Answers | `reflect_mission` | The bank's objective when answering through reflect or mental models. Does not control extraction. |
| Answers | `disposition_skepticism`, `disposition_literalism`, `disposition_empathy` (1–5) | Reflect's reasoning style. |
| Answers | Directives (`…/directives`) | Mandatory reflect rules for language, format, or exclusions, with priority and tags. |
| Answers | Mental models (`…/mental-models`) | Pinned model-generated summaries, consulted first by reflect. |
| Retrieval | `enable_text_search`, `enable_temporal_retrieval`, `enable_graph_retrieval`, `enable_reranking` | Recall pipeline branches. |
| Data | `store_document_text` | Whether to keep source text. |
| Security | `memory_defense` | Memory-poisoning policy in `DefensePolicy` format. |

The reviewed API did not expose an adjustable importance score per fact. Relevance
was controlled at extraction through the mission, `custom` instructions, and
vocabulary, then at consolidation through observation missions and scope-specific
strategies. Tags both filter retrieval and separate consolidation scopes.

Models used by each role remain server settings, configured through environment
variables. See Server & models in the app.

## Reads and audit history

- Per-bank audit logging (`audit_log_enabled`) records actions, transport, requests,
  and complete responses, including facts returned by recall. The app uses this
  for Activity & reads and frequently read facts. Audit logs can contain sensitive
  source content.
- In the reviewed HTTP implementation, `_make_audited_http` in `api/http.py` did not
  record a client identity, user agent, or IP. MCP clients were named. The app
  therefore groups HTTP calls by request signature and lets users name those
  signatures. Use MCP when native agent identification is needed.
- Server 1.0.0 had no per-fact history. From 1.1.0,
  `GET …/documents/{id}/history` records changes to a document and its facts:
  uploads, reprocessing, tags, scope, fact changes, and consolidation. The document
  reader displays this history when available.
- LLM traces for a reflect call show the facts actually supplied to the model.
  The reviewed default retention was one day
  (`HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS`).

## Cost estimates and usage

LLM traces provide model names and token counts for input, output, cache, and
reasoning. The app values them using an editable price book, treats subscription
providers (`claude-code`, `openai-codex`) as quota rather than usage fees, and shows
an equivalent usage-based value. A local ledger retains counters without prompt
or response text beyond the server's trace retention period.

Before imports, reprocessing, consolidation, reflect, or mental-model generation,
the app estimates a range using the bank's observed average per call, falling back
to defaults when needed. These are estimates, not invoices.

Embedding, reranking, and decision-model calls are excluded from generative LLM
quotas, limits, and estimates. Server 1.0.0 did not trace them. From 1.1.0,
`/llm-requests` also includes these services, with `scope` values such as `embedding_*`,
`rerank`, and `decision_*`; the app filters generative reads with `call_type=llm`.

With server 1.2.0, Usage separately shows seven days of specialized-service calls
across banks, grouped by model through `/llm-requests/stats` with `call_type` and
`split_by=model`. These statistics refresh at most every five minutes. Recognized
Hindsight Inference names (`hs-decide-1-flash`, `hs-rerank-1`, `hs-embed-1`) receive an
indicative hosted input-token value. Repository-style local names such as
`hindsight-ai/hs-rerank-1` are not priced. A public model name alone does not prove
a hosted charge: statistics do not identify the provider or endpoint, and a local
decision model may use the same name.

## Merging and renaming banks

- Merge: `POST …/transfer/export` on the source, then
  `POST …/transfer/import?mode=merge` on the target, without LLM generation.
  Facts are re-embedded and entities resolved again. `document_conflict` handles
  document-ID collisions with `skip`, `replace`, or `new-id`.
- Rename: change the display name with `PATCH /banks/{id}`, set a displayed alias
  through `POST …/aliases` with `primary: true`, or obtain a new ID through cloning
  and deletion while preserving the old ID as an alias. Destructive steps require
  their own confirmations.

## External references

- Hindsight: [Best Practices](https://hindsight.vectorize.io/best-practices),
  [Cloud documentation](https://docs.hindsight.vectorize.io),
  [API reference](https://hindsight.vectorize.io/api-reference), and
  [version 0.8.5: per-bank auditing](https://hindsight.vectorize.io/blog/2026/07/21/version-0-8-5).
- Research paper: [Hindsight is 20/20](https://arxiv.org/html/2512.12818v1).
