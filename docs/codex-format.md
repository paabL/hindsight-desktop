> Technical archive: the native Codex reader was removed on 2026-10-29.
> New conversations are exported through Agent Dump into the shared memory folder.

# Observed Codex session format (`~/.codex/sessions`)

This read-only review, dated 2026-10-18, examined file structure: field names, JSON
types, and enum values. No conversation text is reproduced here. The
[synthetic fixture](../Tests/HindsightCoreTests/Fixtures/codex/sample-rollout.jsonl)
contains 19 lines matching the keys, types, and event order of an observed session.
All text, IDs, paths, and timestamps are fictional; its image is a 1×1 PNG.

The historical corpus contained 2,084 files: 2,061 under `sessions/` and 23 under
`archived_sessions/`, with 77 `cli_version` values from `0.35.0` to `0.163.0` and no
invalid JSON lines. These are observations from that corpus, not a current or
complete Codex format specification.

## 1. Locations and files

| Property | Observation |
|---|---|
| Folders | `~/.codex/sessions/YYYY/MM/DD/rollout-<date>-<uuid>.jsonl[.zst]` and the flat `~/.codex/archived_sessions/` folder, which contained only `.jsonl.zst` files. |
| Counts | 411 plain `.jsonl` and 1,650 `.jsonl.zst` files under `sessions/`; 23 `.jsonl.zst` files under `archived_sessions/`. |
| Sizes | `.jsonl`: 47 KB–241 MB, median 451 KB. `.jsonl.zst`: 1 KB–39.6 MB, median 91 KB. |
| Other files | No other file types under `sessions/`. `~/.codex/history.jsonl`, `attachments/`, and `generated_images/` were outside this review. |
| Format | UTF-8 JSON Lines: one object per line. |
| Compression | About 80% of sessions used Zstandard (`.jsonl.zst`), including old and recent sessions. |

At review time, Apple's Compression framework did not decode Zstandard. The former
native importer therefore needed either a bundled decoder, changing the original
no-third-party-dependencies policy, or an external `zstd` executable whose presence
could not be assumed. This was a constraint on that importer, not a description of
the current Agent Dump export path.

Filename dates in `rollout-YYYY-MM-DDThh-mm-ss-<uuid>` represented the machine's local
startup time. Observed offsets from the UTC `session_meta` timestamp were −5, −4,
+1, and +2 hours. Do not treat filenames as authoritative timestamps. The filename
UUID matched `session_meta.payload.id` in 2,061 of 2,082 wrapped-format files; see
section 6 for exceptions.

## 2. Two format generations

| Generation | Files | Line structure |
|---|---:|---|
| Wrapped | 2,082 | `{timestamp, ordinal, type, payload, [metadata]}` |
| Flat, observed only on 2025-09-04 | 2 | First line: `{id, timestamp, instructions, git}`. Later lines: `{record_type}` with `"state"`, or direct `{type: message / reasoning / function_call / function_call_output, …}` items. |

The legacy flat format has no `ordinal`, `payload`, per-line timestamp, or
`event_msg` events. Only two files, about 75 KB each, used it. An importer may skip
those files while reporting “unsupported format.”

## 3. Wrapped envelope

Top-level keys appeared in this order: `timestamp`, `ordinal`, `type`, `payload`,
and sometimes `metadata`.

| Key | Type | Meaning |
|---|---|---|
| `timestamp` | string | UTC ISO 8601 timestamp with milliseconds and a `Z` suffix, 24 characters. |
| `ordinal` | int | Zero-based, strictly increasing line number within a session. One continuity gap was observed in a sample of 339 sessions. |
| `type` | string | Event family; see section 4. |
| `payload` | object | Content. Its own `type` field, when present, is the subtype. |
| `metadata` | object | Mostly on `response_item`: `client_authored` (bool), `user_input_order` (int), `fallback_token_limit_override` (int), `retained_source` (object), and `mcp_attribution` (object). |

### Key information

| Information | Location |
|---|---|
| Session ID | `session_meta.payload.id`, usually the filename UUID. `payload.session_id` identifies the root session. |
| Start time | `session_meta.payload.timestamp`, matching the line's `timestamp`. |
| Working directory | `session_meta.payload.cwd` at startup, then `turn_context.payload.cwd` on each turn; it can change. Also present in `event_msg/thread_settings_applied.payload.thread_settings.cwd`. |
| Codex version | `session_meta.payload.cli_version` (string). |
| Originating client | `session_meta.payload.originator`: `codex_vscode`, `codex_work_desktop`, `Codex Desktop`, `codex-tui`, `codex_exec`, `codex-chrome-extension-sidepanel`, `zed`, `openclaw`, or `hermes`. |
| Model | `turn_context.payload.model`; `session_meta.payload.model_provider` is a string or `null`. |

## 4. Event families

Counts below cover the full wrapped-format corpus.

| `type` | `payload.type` | Count | Purpose |
|---|---|---:|---|
| `session_meta` | — | 2,162 | Header, normally one per file; see section 6 for repeated headers. |
| `event_msg` | `item_completed` | 244,370 | Completed item: message, command, file change, MCP call, reasoning, or subagent activity; see section 5.4. |
| | `token_count` | 136,315 | Token counters and usage limits. |
| | `task_started` / `task_complete` | 16,584 / 16,238 | Start and end of a turn. |
| | `thread_settings_applied` | 13,400 | Thread settings: working directory, model, permissions, and similar values. |
| | `turn_aborted` | 303 | Interrupted turn, with `reason`, such as `interrupted`. |
| | `thread_goal_updated` | 46 | Updated thread goal. |
| `response_item` | `message` | 53,464 | Message with role `user`, `assistant`, or `developer`. |
| | `reasoning` | 117,019 | Reasoning block with encrypted content. |
| | `custom_tool_call` / `custom_tool_call_output` | 61,751 / 61,766 | Free-form tool call, such as `exec` or `apply_patch`, and its output. |
| | `function_call` / `function_call_output` | 36,009 / 36,275 | JSON function call and its output. |
| | `agent_message` | 13,179 | Message from another agent, with encrypted content. |
| | `compaction` | 809 | Encrypted context compaction. |
| | `web_search_call` | 76 | Web search. |
| | `tool_search_call` / `tool_search_output` | 10 / 10 | Deferred-tool discovery. |
| | `additional_tools` | 50 | Added tool catalog. |
| `turn_context` | — | 34,153 | Turn context: working directory, model, sandbox, permissions, and more. |
| `token_usage_record` | — | 75,195 | Token usage per response. |
| `world_state` | — | 3,324 | Environment and available-tool snapshot. |
| `compacted` | — | 769 | Replacement history after compaction. |
| `inter_agent_communication_metadata` | — | 10,398 | Inter-agent metadata, including `trigger_turn` (bool). |
| `retained_context` | `verified_answer` | 119 | Verified answers. |
| `realtime_item` | `transcript_segment` (72), `realtime_session_started` (9), `realtime_session_closed` (9), `bem_item_promoted` (3) | 93 | Voice sessions. |

Families without `payload.type`, including `session_meta`, `turn_context`,
`token_usage_record`, `world_state`, `compacted`, and
`inter_agent_communication_metadata`, store their fields directly in `payload`.

## 5. Family details

JSON types below are `string`, `int`, `float`, `bool`, `null`, `object`, and `array`.
`[]` denotes an array element.

### 5.1 `session_meta`

`payload` fields:

- `id`, `session_id`, `timestamp`, `cwd`, `originator`, and `cli_version`: strings.
- `source`: string or object; see section 6.
- `thread_source`: string; `model_provider`: string or `null`.
- `history_mode`: string, observed as `paginated`.
- `base_instructions`: object or `null`, with `text` and `provenance` containing
  `type` and `model`.
- `context_window`: object containing `window_id`.
- `git`: object containing `branch`, `commit_hash`, and `repository_url`.
- Version-dependent fields: `creator_account_id`, `creator_user_id`, `memory_mode`,
  `multi_agent_version`, `runtime_workspace_roots` (array of strings),
  `dynamic_tools` (array), `parent_thread_id`, `forked_from_id`,
  `forked_from_ordinal_exclusive` (int), `subagent_history_start_ordinal` (int),
  `history_base` (object), `agent_nickname`, and `agent_path`.

The 2,082 inspected headers had 70 distinct field combinations. Only `id`,
`timestamp`, `cwd`, `originator`, `cli_version`, and `history_mode` were consistently
present in those headers. Do not assume other fields exist.

### 5.2 `response_item/message`

`payload` contains `type` (`message`), `id` (string), `role`
(`user`, `assistant`, or `developer`), `content` (array), and optionally `phase`
(for assistants: `commentary` or `final_answer`).
`internal_chat_message_metadata_passthrough` contains `turn_id` (string),
`create_time` (float), and `content_item_kinds` (array of strings).

| Role | `content[].type` | Fields |
|---|---|---|
| `user`, `developer` | `input_text` | `text` |
| `user` | `input_image` | `image_url` (string), `detail` (string, observed as `high`) |
| `assistant` | `output_text` | `text` |

The corpus contained 311,393 user `input_text` blocks, 28,198 assistant
`output_text` blocks, and 81 `input_image` blocks. `agent_message` additionally uses
`encrypted_content` blocks.

#### User-authored text versus injected context

Messages with role `user` also contain context injected by Codex: environment
information, `AGENTS.md`, reminders, and similar material. Where available,
`internal_chat_message_metadata_passthrough.content_item_kinds` distinguishes
these sources. It is parallel to `content[]`, with one entry per block:

- Typed text: `user.text`; attached image: `user.image`.
- Injected context: `environments.environment_context`, `agents_md.instructions`,
  `permissions.instructions`, `host_skills.instructions`, `plugins.recommendations`,
  `plugins.usage_instructions`, `apps.instructions`, `images.resize_notice`,
  `multi_agent.*`, `collaboration_mode.instructions`, `memories.instructions`,
  `guardian.*`, `additional_content.*`, `model_switch.instructions`,
  `model.base_instructions`, `generic.developer_instructions`,
  `generic.turn_aborted`, `user.heartbeat`, and `tools.deferred_namespaces`.
- Assistant content: usually `unknown`.

This field appeared from Codex `0.150`; older sessions, the majority of the corpus,
lack it. Older data needs a heuristic. Excluding blocks beginning with `<…>` or
`# AGENTS.md` was one candidate, but was not validated in this review. Sampled user
messages began with one to three or more `user.text` blocks and could mix typed
text with injected blocks.

### 5.3 Images

Observed images were inline base64 data URIs in `input_image.image_url`, such as
`data:image/png;base64,…`. None of the 81 observed images used a filesystem path or
remote URL in that field; all used `data:image/png`. Their encoded content ranged
from tens to hundreds of KB, and a single line could exceed 700,000 characters.

An image-bearing message used this block sequence and attribution:

1. One or more `input_text` blocks (`user.text`).
2. An opening `input_text` block shaped as `<image name=[Image #N] path="…">`
   (`user.text`). Its `path` is a temporary local path, such as a clipboard image,
   which may no longer exist.
3. The `input_image` block (`user.image`).
4. An `input_text` block containing exactly `</image>` (`user.text`).

The corresponding `event_msg/item_completed` item with type `UserMessage` repeats
image information as `{type: "local_image", path}`, alongside
`{type: "text", text, text_elements}` blocks.

Injected `images.resize_notice` text in a `developer` or `user` message indicates
resizing. Tool results may also contain images: `McpToolCall` results use
`result.content[]` entries with `{type, data, mimeType}`, where `data` is base64.
These are not `input_image` blocks.

### 5.4 `event_msg/item_completed`

`payload` contains `type`, `thread_id`, `turn_id`, `item` (object),
`started_at_ms` (int), and `completed_at_ms` (int). CamelCase `item.type` values
identify subtypes:

| `item.type` | Fields |
|---|---|
| `UserMessage` | `id`, `client_id`, `content[]`: `{type: "text", text, text_elements}` or `{type: "local_image", path}`. |
| `AgentMessage` | `id`, `phase`, `content[]`: `{type: "Text", text}`, with uppercase `T`. |
| `Reasoning` | `id`, `summary_text` (array of strings), `raw_content` (array). |
| `CommandExecution` | `id`, `command` (array of strings), `cwd`, `parsed_cmd[]`, `aggregated_output`, `stdout`, `stderr`, `formatted_output`, `exit_code` (int), `duration` with `secs` and `nanos`, `process_id`, `source`, `status`. |
| `FileChange` | `id`, `changes`: an object keyed by file paths, with values containing `content`, `move_path` (null), `type`, and `unified_diff`; also `stdout`, `stderr`, `status`. |
| `McpToolCall` | `id`, `server`, `tool`, `pluginId`, `arguments` (variable object), `result` containing `content[]`, `isError`, and `_meta`, plus `duration`, `readOnlyHint`, `status`. |
| `WebSearch` | `id`, `query`, `action` containing `type`, `query`, `queries[]`, `url`, and `pattern`; `results[]` containing `title`, `url`, `snippet`, `domain`, `ref_id`, and `type`. |
| `Plan` | `id`, `text`. |
| `SubAgentActivity` | `id`, `kind` (observed as `interacted`), `agent_path`, `agent_thread_id`. |
| `CollabAgentToolCall`, `Extension`, `ContextCompaction` | Variable fields, not detailed here. |

Observed `status` values were `completed` and `failed`; `phase` values were
`final_answer` and `commentary`.

### 5.5 Tool calls in `response_item`

| `payload.type` | Fields |
|---|---|
| `custom_tool_call` | `id`, `call_id`, `name` (`exec` or `apply_patch`), `input` as a string containing code or a patch, `status` (`completed`). |
| `custom_tool_call_output` | `id`, `call_id`, `output`: either an array of `{type: "input_text", text}` objects or a string. |
| `function_call` | `id`, `call_id`, `name`, optional `namespace`, and `arguments` as a JSON string. |
| `function_call_output` | `id`, `call_id`, `output` as a string, sometimes an array. |

`call_id` links a call to its output. Common function names included `exec_command`,
`write_stdin`, `shell`, `shell_command`, `send_message`, `update_plan`, `wait_agent`,
`request_user_input`, and `view_image`. The `text` fields inside
`custom_tool_call_output` often themselves contain serialized JSON, such as results
from JavaScript execution cells.

### 5.6 `reasoning`

`payload` contains `id`, `summary` (an array of `{type: "summary_text", text}` objects,
often empty), and opaque `encrypted_content` (string). Readable reasoning was
almost never available. `item_completed/Reasoning.summary_text` may contain a summary.

### 5.7 Turn events

- `task_started.payload`: `turn_id`, `root_turn_id`, `started_at` (integer seconds),
  `model_context_window` (int), `collaboration_mode_kind` (`default` or `plan`), and
  `turn_attribution` containing `turn_id`, `root_turn_id`, `parent_turn_id` (null),
  `initiating_agent_path` (null), and `turn_trigger`.
- `task_complete.payload`: `turn_id`, `root_turn_id`, `started_at`, `completed_at`
  (seconds), `duration_ms`, `time_to_first_token_ms`, and `last_agent_message` (string).
- Observed `turn_trigger` values: `composer`, `guardian_review`,
  `app_tool_send_message`, `app_tool_create_thread`, `plan_implementation`,
  `automation_heartbeat_scheduled`, `goal`, `send_user_message_async_question`, and
  `chatgpt_handoff`. The field appeared from Codex `0.162`, but not on every turn of
  that version.
- `turn_context.payload`: `cwd`, `model`, `approval_policy`, `sandbox_policy`,
  `permission_profile`, `timezone`, `current_date`, `workspace_roots`, `personality`,
  `effort`, and other fields. These lines were verbose, about 5 KB each.

### 5.8 Unknown or non-conversational events

`token_count`, `token_usage_record`, `thread_settings_applied`, `world_state`,
`turn_context`, `compacted`, `compaction`, `additional_tools`, `tool_search_*`,
`inter_agent_communication_metadata`, `realtime_item/*`, and `retained_context/*`
do not carry exchange text needed by the reviewed conversation importer.

The fixture includes `world_state` and `token_usage_record` to ensure a reader can
ignore unfamiliar types without failing. New types appear between Codex versions.

## 6. Ambiguities and variability

1. **A session is not necessarily a conversation.** Among 2,082 headers,
   `thread_source` was `guardian_review` in 1,018 files, `subagent` in 268, `user` in
   263, absent in 503 older files, `chatgpt_handoff` in 11, `realtime_voice` in 9,
   `voice_chat` in 6, and `agent_created_thread` in 4. Automatic security reviews
   generally offer no conversation content. Only a minority of files represent
   direct user conversations. An importer needs filtering; a missing
   `thread_source` can be treated as “probably user-authored.”
2. **Subagents and reviews use separate files**, linked by `parent_thread_id`.
   Their root `session_id` differs from `id`. `forked_from_id`,
   `forked_from_ordinal_exclusive`, and `subagent_history_start_ordinal` indicate a
   copied thread. A copied file might replay parent history, creating duplicates
   if both are imported. This was inferred from field names, not verified on data.
3. **`source` has two shapes:** a string such as `vscode`, `cli`, or `exec`, or an
   object such as `{subagent: {other: string}}` or
   `{subagent: {thread_spawn: object}}`.
4. **“Task” needs an explicit definition.** A turn spans `task_started` through
   `task_complete` or `turn_aborted`. In a sample of 2,346 turns from 339 sessions
   below 8 MB, 690 had no `user.text` message, 1,457 had one, and 199 had two or
   more. Resumption, heartbeats, other agents, and additional user instructions
   explain why turns and user messages do not map one-to-one. An importer must
   decide whether a task `NNN` follows a turn or an individual user message.
5. **Messages are duplicated** in `response_item/message` and
   `event_msg/item_completed` (`UserMessage` and `AgentMessage`). Counts differed
   slightly: one inspected session had 6 versus 6 user messages and 15 versus 14
   assistant messages. Choose one representation. `response_item` provides
   `role`, `phase`, and inline images; `item_completed` provides local image paths
   and millisecond start/end timestamps.
6. **IDs differed from filenames in 21 of 2,082 files.** Some files repeated
   `session_meta`: 2,162 header lines across 2,082 files. The cause was unresolved,
   possibly copied threads. Do not assume uniqueness; read the first header.
7. **Timestamp units vary:** ISO UTC milliseconds on envelope lines;
   `started_at` and `completed_at` in seconds; `*_at_ms` in milliseconds;
   `create_time` in floating-point seconds; `resets_at` in seconds.
8. **Schemas vary.** Fields such as `metadata`, `phase`, `namespace`,
   `turn_attribution`, and `content_item_kinds` are optional. Decode tolerantly,
   with open enum values. Casing differs:
   `item_completed/UserMessage.content[].type` was `text`, but
   `item_completed/AgentMessage.content[].type` was `Text` in every tested version.
9. **Encrypted content is opaque.** `reasoning.encrypted_content`,
   `agent_message.content[].encrypted_content`, and `compaction.encrypted_content`
   cannot be imported as readable conversation text.
10. **Injected context can be large.** Early session lines contain instructions,
    including multiple KB per `developer` message, `world_state`, and
    `turn_context`. These are not the conversation.
11. **Real files contain personal paths** in `cwd`, `workspace_roots`,
    `FileChange.changes` keys, `<image …>` path attributes, and commands. An
    importer must decide which values to retain. The fixture uses fictional paths.
12. **Stream large files line by line.** Observed files reached 241 MB plain and
    39.6 MB compressed; image-bearing lines could exceed 700,000 characters.
13. **Flat sessions were limited to 2025-09-04** in this corpus; see section 2.
14. **Not checked:** sessions still being written, partial final lines, truncated
    `.jsonl.zst` files, and `~/.codex/history.jsonl`. December 2025 through October
    2026 was best represented in the detailed sample.
