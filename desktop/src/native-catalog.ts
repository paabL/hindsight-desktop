import { getLanguage } from './i18n-core.ts';
import type { Row } from './types';

// Catalogue des seuls libellés fixes du serveur ; jamais appliqué aux valeurs ou aux journaux.
const catalog: Record<string, string> = {
  'Vide = héritage global ; none = désactivé': 'Empty = global inheritance; none = disabled',
  'Modèle propre à cette opération': 'Model specific to this operation',
  'URL propre à cette opération': 'URL specific to this operation',
  'Clé propre à cette opération, masquée': 'Operation-specific key, hidden',
  'Réponses : utiliser la décision': 'Answers: use decision model',
  'Consolidation : utiliser la décision': 'Consolidation: use decision model',
  'Pages de connaissance : décision pendant la régénération':
    'Knowledge pages: decision model during regeneration',
  'Pages de connaissance : filtrage des nouveaux faits': 'Knowledge pages: filter new facts',
  'true (défaut) / false ; une banque peut remplacer ce réglage':
    'true (default) / false; a bank can override this setting',
  'true (défaut) / false': 'true (default) / false',
  'true (défaut) / false ; parcours de repli': 'true (default) / false; fallback workflow',
  'true (défaut) / false ; régénération incrémentale':
    'true (default) / false; incremental regeneration',
  'ChatGPT (connexion du serveur, 1.1.0)': 'ChatGPT (server sign-in, 1.1.0)',
  Fournisseur: 'Provider',
  'ex. claude-code, gemini, openai, anthropic, ollama…':
    'e.g. claude-code, gemini, openai, anthropic, ollama…',
  Modèle: 'Model',
  'Nom exact du modèle ; vide = réglage hérité ou défaut du serveur':
    'Exact model name; empty = inherited setting or server default',
  'URL de base': 'Base URL',
  'Pour un serveur compatible OpenAI, Ollama, LM Studio…':
    'For an OpenAI-compatible server, Ollama, LM Studio…',
  "Clé d'API": 'API key',
  "Conservée dans le script de lancement ; masquée dans l'app":
    'Stored in the launch script; hidden in the app',
  'Requêtes simultanées': 'Concurrent requests',
  'Plafond de concurrence vers ce LLM': 'Maximum concurrent requests to this LLM',
  'Effort de raisonnement': 'Reasoning effort',
  "Niveaux du fournisseur choisi (low, medium, high…) ; vide = réglage hérité ou défaut du fournisseur. Hindsight 1.2 sans modification l'ignore pour claude-code, anthropic, gemini et cursor : un avertissement le signale dans le journal du serveur au démarrage.":
    'Levels of the selected provider (low, medium, high…); empty = inherited setting or provider default. Unmodified Hindsight 1.2 ignores it for claude-code, anthropic, gemini and cursor: a warning in the server log says so at startup.',
  'LLM par défaut': 'Default LLM',
  "Utilisé par tous les rôles qui n'ont pas leurs propres réglages.":
    'Used by all roles without their own settings.',
  'Dossier de connexion Codex': 'Codex sign-in folder',
  'Vide = dossier Codex habituel sur ce Mac': 'Empty = the usual Codex folder on this Mac',
  'Dossier de connexion ChatGPT': 'ChatGPT sign-in folder',
  'Fournisseur chatgpt (serveur 1.1.0) ; vide = ~/.hindsight/chatgpt':
    'chatgpt provider (server 1.1.0); empty = ~/.hindsight/chatgpt',
  'Extraction des faits': 'Fact extraction',
  'LLM qui lit les documents et extrait les faits.': 'LLM that reads documents and extracts facts.',
  Consolidation: 'Consolidation',
  'LLM qui fusionne les faits en observations.': 'LLM that combines facts into observations.',
  'Taille de lot': 'Batch size',
  Parallélisme: 'Parallelism',
  "N'agit qu'entre portées d'observation différentes : les lots d'une même portée passent l'un après l'autre":
    'Only applies across different observation scopes: batches within the same scope run one after another',
  Réponses: 'Answers',
  'LLM qui rédige les réponses à partir de la mémoire.': 'LLM that writes answers from memory.',
  Connaissances: 'Knowledge',
  'LLM qui régénère les connaissances (pages de connaissance et modèles mentaux).':
    'LLM that regenerates knowledge (knowledge pages and mental models).',
  'Vision (VLM)': 'Vision (VLM)',
  'Modèle qui décrit les images des documents.': 'Model that describes document images.',
  'Modèle de décision (1.1.0+ ; Hindsight en 1.2.0)': 'Decision model (1.1.0+; Hindsight in 1.2.0)',
  "Modèle qui répond à des questions typées (choix, score) à la place d'un appel LLM, partagé par la recherche, les réponses, la consolidation et les pages de connaissance. N'écrit pas de texte ; hors plafonds de dépense.":
    'Model that answers typed questions (choices, scores) instead of an LLM call, shared by search, answers, consolidation and knowledge pages. Does not generate text; excluded from spending limits.',
  'none (défaut), hindsight (Hindsight Inference, 1.2.0), typesafe, cloudflare, openai':
    'none (default), hindsight (Hindsight Inference, 1.2.0), typesafe, cloudflare, openai',
  'Vide = défaut du fournisseur (hindsight : hs-decide-1-flash)':
    'Empty = provider default (hindsight: hs-decide-1-flash)',
  'Vide = défaut du fournisseur ; http://127.0.0.1:8766 pour hs-decide-1-flash installé sur ce Mac':
    'Empty = provider default; http://127.0.0.1:8766 for hs-decide-1-flash installed on this Mac',
  "Masquée dans l'app ; hindsight : vide = clé enregistrée par « hindsight-admin cloud login »":
    'Hidden in the app; hindsight: empty = key saved by “hindsight-admin cloud login”',
  'Défaut 24': 'Default: 24',
  'Défaut 60': 'Default: 60',
  'Jetons max par requête': 'Maximum tokens per request',
  'Défaut 26 000 (hindsight : 54 000)': 'Default: 26,000 (hindsight: 54,000)',
  "Vide = celui du dessus, sauf hindsight : la recherche garde alors son reranker tant qu'il n'est pas nommé ici ; none = jamais":
    'Empty = provider above, except hindsight: search keeps its reranker unless explicitly selected here; none = never',
  'Recherche : écarter les faits inutiles': 'Search: prune irrelevant facts',
  'true / false (défaut) ; sans requête de plus. Serveur 1.2.0':
    'true / false (default); no additional request. Server 1.2.0',
  'Recherche : retirer les doublons': 'Search: remove duplicates',
  'true / false (défaut) ; une requête de plus par recherche. Serveur 1.2.0':
    'true / false (default); one additional request per search. Server 1.2.0',
  'Ignoré par un serveur 1.0.0. Le fournisseur hindsight et les options prune/dedup demandent un serveur 1.2.0 ; sans URL locale, il envoie le contenu des faits à Hindsight Inference (Vectorize).':
    'Ignored by server 1.0.0. The hindsight provider and prune/dedup options require server 1.2.0; without a local URL, fact content is sent to Hindsight Inference (Vectorize).',
  'Vectorisation des faits.': 'Fact vectorization.',
  'Modèle Gemini': 'Gemini model',
  'Clé Gemini': 'Gemini key',
  'Dimensions Gemini': 'Gemini dimensions',
  'Modèle OpenAI': 'OpenAI model',
  'Clé OpenAI': 'OpenAI key',
  'Dimensions OpenAI': 'OpenAI dimensions',
  'Modèle LiteLLM': 'LiteLLM model',
  'Clé LiteLLM': 'LiteLLM key',
  'Modèle Google': 'Google model',
  'Projet Google': 'Google project',
  'Clé du compte de service Google': 'Google service account key',
  'Modèle local': 'Local model',
  'Vide = BAAI/bge-small-en-v1.5 ; hindsight-ai/hs-embed-1 (384 dimensions, multilingue, sur CPU)':
    'Empty = BAAI/bge-small-en-v1.5; hindsight-ai/hs-embed-1 (384 dimensions, multilingual, on CPU)',
  'Clé Hindsight Inference': 'Hindsight Inference key',
  'Vide = clé enregistrée par « hindsight-admin cloud login »':
    'Empty = key saved by “hindsight-admin cloud login”',
  "Changer de modèle ou de dimension d'embeddings rend les vecteurs existants incompatibles : la recherche se dégrade jusqu'à une ré-indexation complète (export puis import de la banque).":
    'Changing the embedding model or dimensions makes existing vectors incompatible: search quality suffers until the bank is fully reindexed (export, then import).',
  'Réordonnancement des résultats de recherche.': 'Reranking of search results.',
  'Modèle Cohere': 'Cohere model',
  'Clé Cohere': 'Cohere key',
  'Vide = hindsight-ai/hs-rerank-1 en 1.2.0 (cross-encoder/ms-marco-MiniLM-L-6-v2 avant), sur CPU':
    'Empty = hindsight-ai/hs-rerank-1 in 1.2.0 (previously cross-encoder/ms-marco-MiniLM-L-6-v2), on CPU',
  'Le reranker ne touche pas aux vecteurs : on peut en changer sans ré-indexer. En 1.2.0, le modèle local par défaut devient hs-rerank-1.':
    'The reranker does not change vectors: you can switch it without reindexing. In 1.2.0, the default local model becomes hs-rerank-1.',
  Journalisation: 'Logging',
  'Audit des accès et traces des appels LLM.': 'Access auditing and LLM call traces.',
  "Journal d'audit": 'Audit log',
  'Traces LLM': 'LLM traces',
  "Rétention de l'audit (jours)": 'Audit retention (days)',
  '-1 = pour toujours (défaut)': '-1 = forever (default)',
  'Rétention des traces LLM (jours)': 'LLM trace retention (days)',
  '1 par défaut ; -1 = pour toujours. Plus long = consommation visible plus longtemps':
    'Default: 1; -1 = forever. Longer retention keeps usage visible for longer',
  'Connexion non vérifiée': 'Sign-in not checked',
  'Vérification…': 'Checking…',
  'Session OAuth disponible': 'OAuth session available',
  'Non connecté': 'Not signed in',
  'Terminez la connexion dans le navigateur…': 'Complete sign-in in your browser…',
  'Connexion expirée. Réessayez.': 'Sign-in expired. Try again.',
  'Connexion non terminée. Réessayez ou vérifiez le client officiel.':
    'Sign-in was not completed. Try again or check the official client.',
  'Impossible de lancer la connexion. Vérifiez le client officiel.':
    'Unable to start sign-in. Check the official client.',
  'Déconnexion impossible. Réessayez.': 'Unable to sign out. Try again.',
  'Connexion à effectuer sur la machine du serveur.': "Sign in on the server's machine.",
  'Dossier Codex calculé par le script : précisez son chemin dans les réglages avancés.':
    'The script calculates the Codex folder: enter its path in advanced settings.',
  'hindsight-admin introuvable : il est installé avec le serveur Hindsight.':
    'hindsight-admin was not found: it is installed with the Hindsight server.',
  'Le client ne répond pas. Réessayez.': 'The client is not responding. Try again.',
  'Serveur Hindsight 1.2.0 requis.': 'Hindsight server 1.2.0 is required.',
  'Vérification impossible. Réessayez.': 'Unable to check. Try again.',
  'Statut inconnu. Mettez à jour Claude Code.': 'Unknown status. Update Claude Code.',
  'Vérification impossible. Vérifiez le client officiel.':
    'Unable to check. Check the official client.',
  'valeurs par défaut du serveur': 'server default values',
  'hérite du défaut du serveur': 'inherits the server default',
  'non configuré (défaut du serveur)': 'not configured (server default)',
  'modèle par défaut': 'default model',
  'État inconnu': 'Unknown status',
  'Non installé': 'Not installed',
  'Installé, arrêté': 'Installed, stopped',
  'Démarrage…': 'Starting…',
  'En marche sur ce Mac': 'Running on this Mac',
  "Création de l'environnement Python…": 'Creating the Python environment…',
  'Installation de PyTorch et de ses dépendances (environ 700 Mo)…':
    'Installing PyTorch and dependencies (about 700 MB)…',
  'Téléchargement du modèle hs-decide-1-flash (1,5 Go)…': 'Downloading hs-decide-1-flash (1.5 GB)…',
  'Installation du rendu officiel du modèle…': 'Installing the official model renderer…',
  "Vérification sur l'exemple du modèle…": 'Checking the model example…',
  Vérification: 'Checking',
  "uv est requis pour créer l'environnement Python : https://docs.astral.sh/uv/":
    'uv is required to create the Python environment: https://docs.astral.sh/uv/',
};

export function nativeCatalogText(fr: string): string {
  const operationField = /^(Recherche|Réponses|Consolidation) : (fournisseur|modèle|URL|clé)$/.exec(
    fr,
  );
  if (getLanguage() === 'en' && operationField) {
    const names: Record<string, string> = {
      Recherche: 'Search',
      Réponses: 'Answers',
      Consolidation: 'Consolidation',
    };
    const labels: Record<string, string> = {
      fournisseur: 'provider',
      modèle: 'model',
      URL: 'URL',
      clé: 'key',
    };
    return `${names[operationField[1]]}: ${labels[operationField[2]]}`;
  }
  if (getLanguage() !== 'en') return fr;
  if (Object.hasOwn(catalog, fr)) return catalog[fr];
  const connected = /^Connecté à ([\s\S]+)$/.exec(fr);
  if (connected) return `Connected to ${connected[1]}`;
  const missing = /^(claude|codex) n'est pas installé sur ce Mac\.$/.exec(fr);
  if (missing) return `${missing[1]} is not installed on this Mac.`;
  const environment =
    /^([\s\S]+) : la référence à l'environnement sera remplacée\. Vous pouvez rétablir sa valeur d'origine\.$/.exec(
      fr,
    );
  if (environment)
    return `${nativeCatalogText(environment[1])}: the environment reference will be replaced. You can restore its original value.`;
  const background =
    /^Le script semble lancer le serveur en arrière-plan \(« ([\s\S]+) »\)\. Pour le service, lancez-le au premier plan, par exemple : exec hindsight-api --port 8888$/.exec(
      fr,
    );
  if (background)
    return `The script appears to start the server in the background (“${background[1]}”). For the service, run it in the foreground, for example: exec hindsight-api --port 8888`;
  const unavailable = /^Le serveur local ne répond pas : voir ([\s\S]+)\.$/.exec(fr);
  if (unavailable) return `The local server is not responding: see ${unavailable[1]}.`;
  const write = /^Écriture de ([\s\S]+) impossible\.$/.exec(fr);
  if (write) return `Unable to write ${write[1]}.`;
  const launch = /^(launchctl (?:bootstrap|kickstart)) a échoué : ([\s\S]*)$/.exec(fr);
  if (launch) return `${launch[1]} failed: ${launch[2]}`;
  const timeout = /^([\s\S]+) : délai dépassé\.$/.exec(fr);
  if (timeout && Object.hasOwn(catalog, timeout[1])) return `${catalog[timeout[1]]}: timed out.`;
  const failure = /^([\s\S]+) : échec \(code (-?\d+)\)\. Voir le journal\.$/.exec(fr);
  if (failure && Object.hasOwn(catalog, failure[1]))
    return `${catalog[failure[1]]}: failed (code ${failure[2]}). See the log.`;
  return fr;
}

const fallbackRole: Record<string, string> = {
  retain: 'default',
  consolidation: 'default',
  reflect: 'default',
  mental_model: 'reflect',
};

// Reconstitue uniquement les marqueurs système du résumé. Les noms et valeurs
// viennent des champs bruts et ne passent jamais au dictionnaire de traduction.
export function nativeRoleEffective(role: Row, roles: Row[]): string {
  const original = role.effective;
  if (getLanguage() !== 'en' || typeof original !== 'string') return original;
  const fields: Row[] = role.fields || [];
  const providerField = fields.find((field) => field.name?.endsWith('PROVIDER'));
  if (!providerField) {
    const configured = fields.filter((field) => field.value != null);
    if (!configured.length) return nativeCatalogText(original);
    const expected = configured.map((field) => `${field.label} = ${field.value}`).join(' · ');
    return original === expected
      ? configured.map((field) => `${nativeCatalogText(field.label)} = ${field.value}`).join(' · ')
      : original;
  }
  function configuredValue(item: Row, suffix: string, seen = new Set<string>()): string | null {
    if (seen.has(item.id)) return null;
    seen.add(item.id);
    const value = item.fields?.find((field: Row) => field.name?.endsWith('_' + suffix))?.value;
    if (typeof value === 'string' && value.length) return value;
    const fallback = roles.find((candidate) => candidate.id === fallbackRole[item.id]);
    return fallback ? configuredValue(fallback, suffix, seen) : null;
  }
  const provider = configuredValue(role, 'PROVIDER');
  if (!provider) return nativeCatalogText(original);
  const inherited = providerField.value == null && !!fallbackRole[role.id];
  const source = role.id === 'mental_model' ? 'rôle Réponses' : 'LLM par défaut';
  const suffix = inherited ? ` — hérité du ${source}` : '';
  if (suffix && !original.endsWith(suffix)) return original;
  const base = suffix ? original.slice(0, -suffix.length) : original;
  const prefix = `${provider} · `;
  if (!base.startsWith(prefix)) return original;
  const configuredModel = ['reranker', 'embeddings'].includes(role.id)
    ? null
    : configuredValue(role, 'MODEL');
  const model =
    configuredModel ??
    (base.slice(prefix.length) === 'modèle par défaut'
      ? 'default model'
      : base.slice(prefix.length).replace(/ \(défaut\)$/, ' (default)'));
  return `${prefix}${model}${inherited ? ` — inherited from ${source === 'rôle Réponses' ? 'the Answers role' : 'Default LLM'}` : ''}`;
}
