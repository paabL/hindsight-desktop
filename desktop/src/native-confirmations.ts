import { getLanguage } from './i18n-core.ts';

type Rule = [RegExp, RegExp, (...groups: string[]) => string];

// Les captures sont réinsérées telles quelles. Aucun texte libre n’est recherché ou
// traduit ; une confirmation dont la structure a changé garde son message original.
const rules: Rule[] = [
  [
    /^Changer l'identifiant « .* » en « .* » \?$/,
    /^1\. La banque est copiée vers « (.*) » \(([\d\s,.]+) faits, réglages, directives, webhooks, journaux\) — sans appel LLM\.\n2\. « (.*) » est supprimée\.\n3\. « (.*) » devient un alias de « (.*) » : les clients existants continuent de fonctionner\.\n\nPendant l'opération, une écriture envoyée à « (.*) » peut être perdue : arrêtez les agents qui l'utilisent\.\nPour seulement changer ce qui est affiché, préférez « Nom affiché » ou « Alias affiché »\.$/,
    (target, facts, source, alias, aliasTarget, writeTarget) =>
      `1. The memory bank will be copied to “${target}” (${facts} facts, settings, directives, webhooks and logs), without LLM calls.\n2. “${source}” will be deleted.\n3. “${alias}” will become an alias for “${aliasTarget}”, so existing clients keep working.\n\nWrites sent to “${writeTarget}” during this operation may be lost. Stop agents using it first.\nTo change only the displayed name, use Display name or Display alias instead.`,
  ],
  [
    /^Changer l'identifiant « .* » en « .* » \?$/,
    /^1\. La banque est copiée vers « (.*) » \(([\d\s,.]+) faits, réglages, directives, webhooks, journaux\) — sans appel LLM\.\n2\. « (.*) » est supprimée\.\n3\. Les clients qui utilisent « (.*) » devront être mis à jour\.\n\nPendant l'opération, une écriture envoyée à « (.*) » peut être perdue : arrêtez les agents qui l'utilisent\.\nPour seulement changer ce qui est affiché, préférez « Nom affiché » ou « Alias affiché »\.$/,
    (target, facts, source, clients, writeTarget) =>
      `1. The memory bank will be copied to “${target}” (${facts} facts, settings, directives, webhooks and logs), without LLM calls.\n2. “${source}” will be deleted.\n3. Clients using “${clients}” will need to be updated.\n\nWrites sent to “${writeTarget}” during this operation may be lost. Stop agents using it first.\nTo change only the displayed name, use Display name or Display alias instead.`,
  ],
  [
    /^Fusionner « .* » dans « .* » \?$/,
    /^Les documents de « (.*) » \(([\d\s,.]+) faits\) sont ajoutés à « (.*) » \(([\d\s,.]+) faits\)\.\nSans appel LLM : les faits sont ré-indexés avec le modèle d'embeddings de la cible et leurs entités fusionnées avec celles de la cible\.\nDocuments dont l'identifiant existe déjà dans la cible : (ignorer les documents déjà présents|les importer sous un nouvel identifiant|remplacer ceux de la cible)\.\nLes réglages, directives et modèles mentaux de la source ne sont PAS copiés\. Les observations de la cible seront mises à jour par sa prochaine consolidation \(appels LLM\)\.\n« (.*) » est conservée\.$/,
    (source, sourceFacts, target, targetFacts, conflict, kept) =>
      `${mergeIntro(source, sourceFacts, target, targetFacts, conflict)}\n“${kept}” will be kept.`,
  ],
  [
    /^Fusionner « .* » dans « .* » \?$/,
    /^Les documents de « (.*) » \(([\d\s,.]+) faits\) sont ajoutés à « (.*) » \(([\d\s,.]+) faits\)\.\nSans appel LLM : les faits sont ré-indexés avec le modèle d'embeddings de la cible et leurs entités fusionnées avec celles de la cible\.\nDocuments dont l'identifiant existe déjà dans la cible : (ignorer les documents déjà présents|les importer sous un nouvel identifiant|remplacer ceux de la cible)\.\nLes réglages, directives et modèles mentaux de la source ne sont PAS copiés\. Les observations de la cible seront mises à jour par sa prochaine consolidation \(appels LLM\)\.\n« (.*) » sera ensuite SUPPRIMÉE\.$/,
    (source, sourceFacts, target, targetFacts, conflict, deleted) =>
      `${mergeIntro(source, sourceFacts, target, targetFacts, conflict)}\n“${deleted}” will then be DELETED.`,
  ],
  [
    /^Fusionner « .* » dans « .* » \?$/,
    /^Les documents de « (.*) » \(([\d\s,.]+) faits\) sont ajoutés à « (.*) » \(([\d\s,.]+) faits\)\.\nSans appel LLM : les faits sont ré-indexés avec le modèle d'embeddings de la cible et leurs entités fusionnées avec celles de la cible\.\nDocuments dont l'identifiant existe déjà dans la cible : (ignorer les documents déjà présents|les importer sous un nouvel identifiant|remplacer ceux de la cible)\.\nLes réglages, directives et modèles mentaux de la source ne sont PAS copiés\. Les observations de la cible seront mises à jour par sa prochaine consolidation \(appels LLM\)\.\n« (.*) » sera ensuite SUPPRIMÉE, et son identifiant mènera à « (.*) »\.$/,
    (source, sourceFacts, target, targetFacts, conflict, deleted, aliasTarget) =>
      `${mergeIntro(source, sourceFacts, target, targetFacts, conflict)}\n“${deleted}” will then be DELETED, and its identifier will point to “${aliasTarget}”.`,
  ],
  [
    /^Afficher « .* » sous le nom « .* » \?$/,
    /^« (.*) » devient un second identifiant de la même banque, affiché à sa place\. Rien n'est copié ; « (.*) » continue de fonctionner partout\. Les journaux et exports gardent l'identifiant d'origine\.$/,
    (alias, original) =>
      `“${alias}” will become a second identifier for the same memory bank and will be displayed instead. Nothing is copied. “${original}” keeps working everywhere. Logs and exports retain the original identifier.`,
  ],
  [
    /^Cloner « .* » vers « .* » \?$/,
    /^Une nouvelle banque est créée \(elle ne doit pas exister\)\. Sans appel LLM : faits ré-indexés, entités résolues à nouveau\.( Attention : la configuration copiée inclut les webhooks de la banque source\.)?$/,
    (warning) =>
      `A new memory bank will be created; it must not already exist. No LLM calls: facts are reindexed and entities resolved again.${warning ? ' Warning: the copied configuration includes the source memory bank’s webhooks.' : ''}`,
  ],
  [
    /^Fusionner l'archive dans « .* » \?$/,
    /^Les documents de l'archive sont ajoutés\. Documents déjà présents : (REMPLACÉS|importés sous un nouvel identifiant|ignorés)\.$/,
    (conflict) =>
      `Documents from the archive will be added. Existing documents: ${conflict === 'REMPLACÉS' ? 'REPLACED' : conflict === 'ignorés' ? 'skipped' : 'imported with a new identifier'}.`,
  ],
  [
    /^Restaurer l'archive dans une nouvelle banque \?$/,
    /^La banque « (.*) » sera créée ; elle ne doit pas exister\.$/,
    (bank) => `Memory bank “${bank}” will be created; it must not already exist.`,
  ],
  [
    /^(Réinstaller|Installer) le service Hindsight \?$/,
    /^Script exécuté : (.*)\nEmpreinte SHA-256 : (.*)\nAgent launchd : (.*)\nJournal : (.*)\nDémarrage à l'ouverture de session : (oui|non)(\nLe script sera rendu exécutable pour vous \(chmod u\+x\)\.)?(?:\nAttention : (.*))?(\nLe service en cours sera redémarré avec cette configuration\.)?\n\nCe script s'exécutera avec vos droits\. N'approuvez qu'un fichier dont vous connaissez le contenu\.$/,
    (script, hash, agent, log, login, executable, warning, restart) =>
      `Script to run: ${script}\nSHA-256 fingerprint: ${hash}\nlaunchd agent: ${agent}\nLog: ${log}\nStart at login: ${login === 'oui' ? 'yes' : 'no'}${executable ? '\nThe script will be made executable for you (chmod u+x).' : ''}${warning ? '\nWarning: ' + warning : ''}${restart ? '\nThe running service will restart with this configuration.' : ''}\n\nThis script will run with your permissions. Approve only a file whose contents you understand.`,
  ],
  [
    /^Le script de lancement a changé$/,
    /^(.*) a été modifié hors de l'app depuis votre dernière approbation \(empreinte (.*)…\)\.\n\nVérifiez son contenu avant de l'exécuter\.$/,
    (script, hash) =>
      `${script} has changed outside the app since your last approval (fingerprint ${hash}…).\n\nReview its contents before running it.`,
  ],
  [
    /^Installer le modèle de décision sur ce Mac \?$/,
    /^Dans (.*) :\n• un environnement Python 3\.13 à part \(uv\), avec PyTorch, transformers et pydantic depuis PyPI \(environ 700 Mo\) ;\n• le modèle (.*) depuis Hugging Face, à la révision (.*) \(1,5 Go\) ;\n• son rendu officiel \(dossier serving\/ du modèle\) et un serveur local, vérifié sur l'exemple du modèle\.\n\nLe service démarre à l'ouverture de session et n'écoute que 127\.0\.0\.1:(\d+)\. Il occupe environ 2 Go de mémoire\.$/,
    (path, model, revision, port) =>
      `In ${path}:\n• a separate Python 3.13 environment (uv), with PyTorch, transformers and pydantic from PyPI (about 700 MB);\n• model ${model} from Hugging Face, at revision ${revision} (1.5 GB);\n• its official rendering code (the model’s serving/ folder) and a local server, checked against the model’s example.\n\nThe service starts at login and listens only on 127.0.0.1:${port}. It uses about 2 GB of memory.`,
  ],
  [
    /^Recompiler l'app \?$/,
    /^Compilation de ([\s\S]*) \(quelques minutes ; la copie locale sera compilée avec vos droits\), puis remplacement de l'app([\s\S]*)\.$/,
    (repository, app) =>
      `Build ${repository} (a few minutes; this local copy will be built with your permissions), then replace the app${app}.`,
  ],
  [
    /^Ajouter \d+ document\(s\) \?$/,
    /^Projet : (.*)\nDestination : (.*)\n\n([\s\S]*)\n\nLe collecteur de ce dossier copie les originaux et actualise uniquement le catalogue local\. Aucun envoi ni traitement Hindsight ; les quatre collecteurs externes ne sont pas lancés\.$/,
    (project, destination, names) =>
      `Project: ${project}\nDestination: ${destination}\n\n${names}\n\nThis folder's collector copies the originals and updates only the local catalog. Nothing is uploaded or processed by Hindsight. The four external collectors are not run.`,
  ],
  [
    /^Vérifier ou reprendre l’envoi initial \?$/,
    /^Le même lot de (\d+) sources sera présenté au serveur avec son identifiant initial\. Un lot déjà accepté ne sera pas extrait deux fois\. Le texte est celui de l’aperçu initial\.\n\n([\s\S]*)$/,
    (count, ids) =>
      `The same batch of ${count} sources will be sent to the server with its original identifier. A previously accepted batch will not be extracted twice. The text comes from the original preview.\n\n${ids}`,
  ],
  [
    /^Lancer cette opération maintenant \?$/,
    /^« ([\s\S]*) » attend sa prochaine tentative([\s\S]*)\. Elle sera lancée tout de suite ; selon son type, cela peut consommer des appels LLM\.$/,
    (name, when) =>
      `“${name}” is waiting for its next retry${when}. It will run immediately. Depending on its type, this may use LLM calls.`,
  ],
];

function mergeIntro(
  source: string,
  sourceFacts: string,
  target: string,
  targetFacts: string,
  conflict: string,
) {
  const conflicts: Record<string, string> = {
    'ignorer les documents déjà présents': 'skip existing documents',
    'les importer sous un nouvel identifiant': 'import them with a new identifier',
    'remplacer ceux de la cible': 'replace the target documents',
  };
  return `Documents from “${source}” (${sourceFacts} facts) will be added to “${target}” (${targetFacts} facts).\nNo LLM calls: facts are reindexed with the target’s embedding model and their entities merged with the target’s entities.\nDocuments whose identifiers already exist in the target: ${conflicts[conflict]}.\nThe source’s settings, directives and summaries are NOT copied. Target observations will be updated by its next consolidation (LLM calls).`;
}

function restartMessage(message: string): string {
  const warning =
    "Le script a été modifié hors de l'app depuis votre dernière approbation : vérifiez-le.\n\n";
  const changed = message.startsWith(warning);
  const body = changed ? message.slice(warning.length) : message;
  const lead = changed
    ? 'The script has changed outside the app since your last approval. Review it first.\n\n'
    : '';
  const simple =
    'Les requêtes en cours seront interrompues ; les opérations en file reprendront au redémarrage.';
  if (body === simple)
    return (
      lead +
      'Current requests will be interrupted. Queued operations will resume after the restart.'
    );
  const suffix =
    "\n\nLes requêtes en cours seront interrompues ; les opérations en file seront reprises par le serveur à son redémarrage. L'app attend ensuite que l'API réponde puis teste les LLM.";
  if (!body.endsWith(suffix)) return message;
  const start = body.slice(0, -suffix.length);
  const tail =
    '\n\nCurrent requests will be interrupted. Queued operations will resume when the server restarts. The app then waits for the API to respond and tests the LLMs.';
  if (start.startsWith('Commande exécutée sur ce Mac :\n'))
    return (
      lead +
      'Command run on this Mac:\n' +
      start.slice('Commande exécutée sur ce Mac :\n'.length) +
      tail
    );
  const match = /^Le service de l'app relance ([\s\S]*)\.$/.exec(start);
  return match ? lead + `The app's service restarts ${match[1]}.` + tail : message;
}

function installUpdateMessage(message: string): string {
  const suffix =
    "\nCe code sera compilé puis exécuté sur ce Mac, avec vos droits. N'acceptez que des commits d'une source de confiance.\nL'app sera remplacée ; il suffira ensuite de la relancer.";
  if (!message.endsWith(suffix)) return message;
  const body = message.slice(0, -suffix.length);
  const match =
    /^(?:⚠︎ Le dépôt distant a changé depuis la dernière mise à jour \(avant : (.*)\)\.\n)?Dépôt : (.*)\nBranche : (.*) → (.*)\n(\d+) commit\(s\) :\n([\s\S]*)$/.exec(
      body,
    );
  if (!match) return message;
  const [, previous, repository, branch, commit, count, commits] = match;
  return (
    (previous
      ? `⚠ The remote repository has changed since the last update (previously: ${previous}).\n`
      : '') +
    `Repository: ${repository}\nBranch: ${branch} → ${commit}\n${count} commit(s):\n${commits}\nThis code will be built and then run on this Mac with your permissions. Accept only commits from a trusted source.\nThe app will be replaced. Relaunch it afterwards.`
  );
}

export function advancedConfirmationMessage(title: string, message: string): string {
  if (getLanguage() !== 'en') return message;
  if (title === 'Redémarrer le serveur Hindsight ?') return restartMessage(message);
  if (title === 'Installer la mise à jour ?') return installUpdateMessage(message);
  for (const [titlePattern, messagePattern, render] of rules) {
    if (!titlePattern.test(title)) continue;
    const match = messagePattern.exec(message);
    if (match) return render(...match.slice(1));
  }
  return message;
}
