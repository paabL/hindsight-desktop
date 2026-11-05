# Model settings diagram

**Models** is a primary sidebar destination, next to Search. It contains quick selectors and the explanatory diagram, and is available without a selected memory bank. **Manage models** opens Settings → Server & models for providers, installation, accounts, custom models and advanced configuration. Both views share one draft, so navigating between them preserves prepared choices.

![Model choices and the Answer decision loop — fictional data](images/hindsight-desktop.png)

The diagram shows the launch-script draft, not the state of an already running process. Save reviews the changes through the existing confirmation; applying the saved settings restarts the server through a separate confirmed action. Bank-specific behavior settings can override server defaults.

In **Answer**, one reflection model writes search queries and the final answer. Without a specialized decision model, search results return to that model, which decides whether to search again. With one, the decision model filters evidence and checks sufficiency; insufficient evidence returns to reflection for another query. These are simplified paths: budget limits and server fallback behavior still apply.

**Search** ranking and **Answer** evidence evaluation are independent. Hindsight's global decision provider does not automatically replace recall's reranker. Search must explicitly select it. When enabled, the Answer diagram links its ranking stage to Search. A per-operation model, URL or key override is displayed as a separate configuration rather than falsely labelled as shared. Pages use the reflection decision client; their two behavior flags remain available in advanced settings.

Each role has a short explanation on hover, keyboard focus or tap. Provider changes, custom model identifiers, vision, default models, keys and per-operation overrides stay in Settings. Installation/start/stop and Cloud connection controls remain available under model services. Quick selection offers existing model choices and keeps unconnected Cloud destinations unavailable. Embeddings are read-only in the diagram.

The diagram prepares only allowed model names and decision flags, with an optimistic revision check against the current script draft. It cannot change embeddings, credentials or endpoints through the batch command. Dynamic shell values must be edited explicitly through advanced settings. No selection triggers ingestion, inference or a server restart.

In Settings, Provider and Model are dropdowns. Switching provider updates the model menu inside the modal, without changing the native draft until Prepare is selected. The menus include configured custom providers/models and the existing native catalog; Codex also uses its local public model catalog. Cancel discards these modal choices. Provider-specific embedding and reranker fields remain independent.

Only the selected provider's applicable advanced fields are shown. **Other model…**
opens an explicit custom-name field when a configured identifier is not in the
catalog. This is separate from choosing an existing model in the quick view.

![Account connection indicators — fictional data](images/hindsight-accounts.png)

Green means a session is available or the account is signed in. Red means
disconnected, unavailable or failed; amber means checking or connecting; gray
means unchecked. The status text remains visible. These indicators do not test
whether a particular model is accessible or whether subscription quota remains.

Validation:

- `swift test --disable-sandbox -c release --filter 'ModelWorkflowTests|ServerSettingsViewModelTests'`
- `cd desktop && npm run bridge:build && npm test`
- `cd desktop && node tests/model-workflow-ui.mjs`
- `cd desktop && npm run test:models && npm run test:navigation && npm run test:i18n`

The native test uses temporary launch scripts and a local HTTP fixture, verifies confirmation and replay protection, and checks that existing embedding lines and secrets are preserved. Browser checks use only the fictional demo state.
